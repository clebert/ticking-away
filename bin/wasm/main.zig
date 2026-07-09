const std = @import("std");

const lib = @import("lib");

comptime {
    // JS reads render()'s result as a flat RGBA Uint8ClampedArray (src/renderer.ts),
    // so Srgb must be exactly r, g, b, a with no padding. Auto layout does not
    // guarantee this, so pin it:
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

// A single grow-only contiguous arena backed by @wasmMemoryGrow, reused across
// frames. Exact page-count growth avoids the allocator's power-of-two rounding so a
// native full-res frame fits tightly (a 6K canvas takes ~407 MB, not ~642 MB).
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

    // usize is u32 on wasm32 and this module runs without runtime safety, so an oversize
    // frame would wrap these size products silently and under-size the arena (a heap
    // overflow). Use checked arithmetic and return null on overflow.
    const pixel_count = std.math.mul(usize, image_width, image_height) catch return null;
    // Sized for dither.pebble (3 channels), the larger of the two dithers, so either
    // texture's error buffer fits when the config switches at runtime.
    const error_count = lib.dither.pebble.errorBufferSize(image_width);

    // Lay the buffers out by descending alignment so every offset stays naturally
    // aligned: Linear (16 B) first, then Srgb (4 B), then the f32 error rows.
    const linear_bytes = std.math.mul(usize, pixel_count, @sizeOf(lib.Linear)) catch return null;
    const srgb_bytes = std.math.mul(usize, pixel_count, @sizeOf(lib.Srgb)) catch return null;
    const error_bytes = std.math.mul(usize, error_count, @sizeOf(f32)) catch return null;
    const error_offset = std.math.add(usize, linear_bytes, srgb_bytes) catch return null;
    const total_bytes = std.math.add(usize, error_offset, error_bytes) catch return null;

    arenaReserve(total_bytes) catch return null;

    const linear_buffer = arenaSlice(lib.Linear, 0, pixel_count);
    const srgb_buffer = arenaSlice(lib.Srgb, linear_bytes, pixel_count);
    const dither_error_buffer = arenaSlice(f32, error_offset, error_count);

    const image = lib.Image.init(image_width, image_height);

    _ = lib.frame.render(
        &config,
        lib.Time.init(hour, minute),
        image,
        linear_buffer,
        srgb_buffer,
        dither_error_buffer,
    ) catch return null;

    return @ptrCast(srgb_buffer.ptr);
}
