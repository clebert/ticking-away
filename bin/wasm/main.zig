const std = @import("std");
const allocator = std.heap.wasm_allocator;

const lib = @import("lib");

var config_json_buffer: [1024]u8 = undefined;
var parse_buffer: [4096]u8 = undefined;
var cached_config: ?lib.Config = null;

export fn getConfigJsonBufferPtr() [*]u8 {
    return &config_json_buffer;
}

fn getConfig(config_json_byte_length: u32) ?lib.Config {
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
var dither_error_buffer: ?[]f32 = null;
var last_width: usize = 0;
var last_height: usize = 0;

fn ensureBuffers(width: usize, height: usize) error{OutOfMemory}!void {
    if (width == last_width and
        height == last_height and
        linear_buffer != null and
        srgb_buffer != null and
        dither_error_buffer != null) return;

    if (linear_buffer) |buffer| allocator.free(buffer);
    if (srgb_buffer) |buffer| allocator.free(buffer);
    if (dither_error_buffer) |buffer| allocator.free(buffer);

    linear_buffer = null;
    srgb_buffer = null;
    dither_error_buffer = null;

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

    dither_error_buffer = try allocator.alloc(f32, lib.Dither.errorBufferSize(width));

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

    const clock = lib.Clock.init(
        lib.Time.init(hour, minute),
        config.prism_normalized_size,
        config.rainbow_normalized_spread,
    );

    const image = lib.Image.init(@intCast(width), @intCast(height));

    @memset(
        linear_buffer.?,
        if (config.background_enabled) lib.Linear.black else lib.Linear.transparent,
    );

    var linear_band =
        image.band(lib.Linear, linear_buffer.?, @intCast(height), 0) catch return null;

    const viewport = image.viewport();

    const watchface = lib.Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .hand_glow_falloff = config.hand_glow_falloff,
        .hand_length_falloff = config.hand_length_falloff,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .prism_glow_falloff = config.prism_glow_falloff,
        .prism_glow_color = lib.Linear.init(0.1, config.prism_glow_linear_green, 1.0, 1.0),
        .rainbow_palette_id = if (config.dither_enabled)
            config.dither_rainbow_palette_id
        else
            config.rainbow_palette_id,
    };

    watchface.render(linear_band, viewport, clock);

    const srgb_band = if (config.dither_enabled) blk: {
        const dither = lib.Dither{
            .normalized_strength = config.dither_normalized_strength,
            .normalized_chroma_emphasis = config.dither_normalized_chroma_emphasis,
            .palette = config.dither_palette_id.palette(),
        };

        break :blk dither.apply(
            linear_band,
            srgb_buffer.?,
            dither_error_buffer.?,
        ) catch return null;
    } else blk: {
        break :blk linear_band.toSrgb(srgb_buffer.?) catch return null;
    };

    if (config.grain_enabled) {
        const grain = lib.Grain{
            .normalized_deviation = config.grain_normalized_deviation,
            .dither_palette = if (config.dither_enabled)
                config.dither_palette_id.palette()
            else
                null,
        };

        grain.apply(srgb_band);
    }

    if (config.background_enabled) {
        const crop = lib.Crop{
            .outside_color = lib.Srgb.transparent,
            .antialias = !config.dither_enabled,
        };

        crop.apply(srgb_band, viewport);
    }

    return @ptrCast(srgb_buffer.?.ptr);
}
