const std = @import("std");
const allocator = std.heap.wasm_allocator;

const lib = @import("lib");

const GlowFalloff = enum(i32) {
    linear = 0,
    quadratic = 1,
    cubic = 2,
    exponential = 3,

    fn toLib(self: GlowFalloff) lib.Glow.Falloff {
        return switch (self) {
            .linear => .linear,
            .quadratic => .quadratic,
            .cubic => .cubic,
            .exponential => .exponential,
        };
    }
};

const RainbowPalette = enum(i32) {
    oklch_balanced = 0,
    spectral = 1,
    spectra6 = 2,

    fn toLib(self: RainbowPalette) lib.Rainbow.PaletteId {
        return switch (self) {
            .oklch_balanced => .oklch_balanced,
            .spectral => .spectral,
            .spectra6 => .spectra6,
        };
    }
};

const DitherPalette = enum(i32) {
    ideal = 0,
    spectra6_inky = 1,
    spectra6_epdopt = 2,
    spectra6_trmnl = 3,

    fn toLib(self: DitherPalette) lib.Dither.PaletteId {
        return switch (self) {
            .ideal => .ideal,
            .spectra6_inky => .spectra6_inky,
            .spectra6_epdopt => .spectra6_epdopt,
            .spectra6_trmnl => .spectra6_trmnl,
        };
    }
};

const Config = extern struct {
    hour: i32,
    minute: f32,
    normalized_prism_size: f32,
    normalized_rainbow_spread: f32,
    prism_glow_srgb_red: i32,
    prism_glow_srgb_green: i32,
    prism_glow_srgb_blue: i32,
    normalized_prism_glow_width: f32,
    prism_glow_falloff: GlowFalloff,
    normalized_hand_glow_width: f32,
    hand_glow_falloff: GlowFalloff,
    rainbow_palette_id: RainbowPalette,
    normalized_grain_intensity: f32,
    device_pixel_ratio: f32,
    dither_enabled: i32,
    dither_palette_id: DitherPalette,
    normalized_dither_strength: f32,
    normalized_dither_chroma_emphasis: f32,
};

var config: Config = undefined;

export fn getConfigPtr() *Config {
    return &config;
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

export fn render(width: u32, height: u32) ?[*]u8 {
    ensureBuffers(@intCast(width), @intCast(height)) catch return null;

    const time = lib.Time.init(@intCast(config.hour), config.minute);

    const prism = lib.Prism.init(std.math.clamp(config.normalized_prism_size, 0.01, 1.0));
    const clock = lib.Clock.init(time, prism, std.math.clamp(config.normalized_rainbow_spread, 0.0, 1.0));

    @memset(linear_buffer.?, lib.Linear.black);

    const image = lib.Image.init(@intCast(width), @intCast(height));

    var linear_band = image.band(lib.Linear, linear_buffer.?, @intCast(height), 0) catch return null;

    const viewport = image.viewport();

    const watchface = lib.Watchface{
        .hand_glow_style = .{
            .normalized_width = config.normalized_hand_glow_width,
            .falloff = config.hand_glow_falloff.toLib(),
        },
        .prism_glow_style = .{
            .normalized_width = config.normalized_prism_glow_width,
            .falloff = config.prism_glow_falloff.toLib(),
        },
        .prism_glow_color = lib.Linear.init(
            @as(f32, @floatFromInt(config.prism_glow_srgb_red)) / 255.0,
            @as(f32, @floatFromInt(config.prism_glow_srgb_green)) / 255.0,
            @as(f32, @floatFromInt(config.prism_glow_srgb_blue)) / 255.0,
            1.0,
        ),
        .rainbow_palette_id = config.rainbow_palette_id.toLib(),
    };

    watchface.render(&linear_band, viewport, prism, clock);

    var srgb_band = if (config.dither_enabled != 0) blk: {
        const dither = lib.Dither{
            .normalized_strength = config.normalized_dither_strength,
            .normalized_chroma_emphasis = config.normalized_dither_chroma_emphasis,
            .palette = config.dither_palette_id.toLib().palette(),
        };

        break :blk dither.apply(linear_band, srgb_buffer.?, dither_error_buffer.?) catch return null;
    } else blk: {
        break :blk linear_band.toSrgb(srgb_buffer.?) catch return null;
    };

    const grain = lib.Grain{
        .normalized_intensity = config.normalized_grain_intensity,
        .normalized_size = config.device_pixel_ratio * viewport.inverse_scale,
    };

    grain.apply(&srgb_band, viewport);

    const crop = lib.Crop{ .outside_color = lib.Srgb.transparent };

    crop.apply(&srgb_band, viewport);

    return @ptrCast(srgb_buffer.?.ptr);
}
