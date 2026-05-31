const std = @import("std");
const allocator = std.heap.wasm_allocator;

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

var linear_buffer: ?[]lib.Linear = null;
var srgb_buffer: ?[]lib.Srgb = null;
var last_width: usize = 0;
var last_height: usize = 0;

fn ensureBuffers(width: usize, height: usize) error{OutOfMemory}!void {
    if (width == last_width and
        height == last_height and
        linear_buffer != null and
        srgb_buffer != null) return;

    if (linear_buffer) |buffer| allocator.free(buffer);
    if (srgb_buffer) |buffer| allocator.free(buffer);

    linear_buffer = null;
    srgb_buffer = null;

    const pixel_count = width * height;

    linear_buffer = try allocator.alloc(lib.Linear, pixel_count);

    errdefer {
        allocator.free(linear_buffer.?);
        linear_buffer = null;
    }

    srgb_buffer = try allocator.alloc(lib.Srgb, pixel_count);

    errdefer {
        allocator.free(srgb_buffer.?);
        srgb_buffer = null;
    }

    last_width = width;
    last_height = height;
}

export fn render(
    width: u32,
    height: u32,
    hour: u32,
    minute: f32,
    config_json_byte_length: u32,
) ?[*]u8 {
    const config = getConfig(config_json_byte_length) orelse return null;

    ensureBuffers(@intCast(width), @intCast(height)) catch return null;

    const image = lib.Image.init(@intCast(width), @intCast(height));

    _ = lib.frame.render(
        config,
        lib.Time.init(hour, minute),
        image,
        linear_buffer.?,
        srgb_buffer.?,
    ) catch return null;

    return @ptrCast(srgb_buffer.?.ptr);
}
