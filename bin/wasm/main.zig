const std = @import("std");

const lib = @import("lib");

comptime {
    // render() returns a pointer that JS reinterprets as a flat RGBA byte buffer
    // (a Uint8ClampedArray over WASM memory; see src/renderer.ts). That contract
    // requires lib.Srgb to be exactly 4 bytes laid out as r, g, b, a with no
    // padding. lib.Srgb has the default (auto) layout, which the language does
    // not guarantee — pin the assumption here so a layout change fails the build
    // instead of silently producing garbled pixels.
    std.debug.assert(@sizeOf(lib.Srgb) == 4);
    std.debug.assert(@offsetOf(lib.Srgb, "r") == 0);
    std.debug.assert(@offsetOf(lib.Srgb, "g") == 1);
    std.debug.assert(@offsetOf(lib.Srgb, "b") == 2);
    std.debug.assert(@offsetOf(lib.Srgb, "a") == 3);
}

var config_json_buffer: [1024]u8 = undefined;
var parse_buffer: [4096]u8 = undefined;
var cached_config: ?lib.Config = null;

export fn getConfigJsonBufferPtr() [*]u8 {
    return &config_json_buffer;
}

export fn getConfigJsonBufferSize() u32 {
    return config_json_buffer.len;
}

fn getConfig(config_json_byte_length: u32) ?lib.Config {
    // A length of 0 is the "config unchanged, reuse cache" signal that
    // writeConfigJson (src/config.tsx) emits when neither the config nor the
    // WASM memory buffer has changed since the last write.
    if (config_json_byte_length == 0) return cached_config;

    var fixed_buffer = std.heap.FixedBufferAllocator.init(&parse_buffer);

    cached_config = lib.Config.parse(
        fixed_buffer.allocator(),
        config_json_buffer[0..config_json_byte_length],
    ) catch return null;

    return cached_config;
}

// A single grow-only arena for the render buffers, backed directly by
// @wasmMemoryGrow. Growing by exact page counts (rather than through the general
// allocator, which rounds large allocations up to a power of two) lets a native
// full-resolution frame fit tightly — e.g. a 6K canvas needs ~407 MB, not ~642 MB.
// One contiguous region reused across frames means peak memory equals the largest
// frame ever rendered, with no fragmentation or resize accumulation.
var arena_base: usize = 0;
var arena_bytes: usize = 0;
var arena_initialized: bool = false;

fn arenaReserve(bytes: usize) error{OutOfMemory}!void {
    if (bytes <= arena_bytes) return;

    const grow_pages = (bytes - arena_bytes + std.wasm.page_size - 1) / std.wasm.page_size;
    const previous = @wasmMemoryGrow(0, grow_pages);

    if (previous < 0) return error.OutOfMemory;

    // We own every growable page (nothing else grows memory), so the arena starts at
    // the first grown page and stays contiguous as it grows.
    if (!arena_initialized) {
        arena_base = @as(usize, @intCast(previous)) * std.wasm.page_size;
        arena_initialized = true;
    }

    arena_bytes += grow_pages * std.wasm.page_size;
}

fn arenaSlice(comptime T: type, offset: usize, count: usize) []T {
    const pointer: [*]T = @ptrFromInt(arena_base + offset);

    return pointer[0..count];
}

export fn render(
    width: u32,
    height: u32,
    hour: u32,
    minute: f32,
    config_json_byte_length: u32,
) ?[*]u8 {
    const config = getConfig(config_json_byte_length) orelse return null;

    const image_width: usize = @intCast(width);
    const image_height: usize = @intCast(height);

    const supersample_factor = lib.frame.supersampleFactor(config);

    // usize is u32 on wasm32 and this module is built without runtime safety, so the
    // buffer-size products below would wrap silently for an oversize frame, under-sizing
    // the arena while the slices still span the true pixel count — a heap overflow. Reject
    // any frame whose arena footprint does not fit usize; the JS caller treats a null return
    // as "render failed, keep the previous frame".
    const pixel_count = std.math.mul(usize, image_width, image_height) catch return null;
    const supersampled_count = std.math.mul(usize, pixel_count, supersample_factor * supersample_factor) catch return null;
    const error_count = lib.dither.errorBufferSize(image_width);

    // Lay the three buffers out consecutively in the arena: Linear (16 B, the strictest
    // alignment) first, then Srgb (4 B), then the f32 error rows — each offset is a multiple
    // of the next type's size, so every slice stays naturally aligned. The Linear scratch
    // holds the full supersampled render; downsampling rewrites its front in place.
    const linear_bytes = std.math.mul(usize, supersampled_count, @sizeOf(lib.Linear)) catch return null;
    const srgb_bytes = std.math.mul(usize, pixel_count, @sizeOf(lib.Srgb)) catch return null;
    const error_bytes = std.math.mul(usize, error_count, @sizeOf(f32)) catch return null;
    const error_offset = std.math.add(usize, linear_bytes, srgb_bytes) catch return null;
    const total_bytes = std.math.add(usize, error_offset, error_bytes) catch return null;

    arenaReserve(total_bytes) catch return null;

    const linear_buffer = arenaSlice(lib.Linear, 0, supersampled_count);
    const srgb_buffer = arenaSlice(lib.Srgb, linear_bytes, pixel_count);
    const dither_error_buffer = arenaSlice(f32, error_offset, error_count);

    const image = lib.Image.init(image_width, image_height);

    _ = lib.frame.render(
        config,
        lib.Time.init(hour, minute),
        image,
        linear_buffer,
        srgb_buffer,
        dither_error_buffer,
    ) catch return null;

    return @ptrCast(srgb_buffer.ptr);
}
