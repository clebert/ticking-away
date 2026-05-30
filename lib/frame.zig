const std = @import("std");

const Clock = @import("Clock.zig");
const Config = @import("Config.zig");
const Crop = @import("Crop.zig");
const Dither = @import("Dither.zig");
const Grain = @import("Grain.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");
const Time = @import("Time.zig");
const Watchface = @import("Watchface.zig");

/// Renders a single watchface frame from `config` into `srgb_buffer` and returns
/// the resulting sRGB band. `linear_buffer` and `srgb_buffer` must each hold
/// exactly `image.width * image.height` pixels.
///
/// Dithering (the 6-color e-ink path) is applied only when `config.dither_enabled`
/// is true AND a `dither_error_buffer` is supplied. Passing `null` forces
/// full-color output regardless of config — the PNG export does this because it
/// is a full-color renderer (see bin/png/main.zig).
pub fn render(
    config: Config,
    time: Time,
    image: Image,
    linear_buffer: []Linear,
    srgb_buffer: []Srgb,
    dither_error_buffer: ?[]f32,
) !Image.Band(Srgb) {
    const dithering = config.dither_enabled and dither_error_buffer != null;

    const clock = Clock.init(
        time,
        config.prism_normalized_size,
        config.rainbow_normalized_spread,
    );

    const viewport = image.viewport();

    @memset(
        linear_buffer,
        if (config.background_enabled) Linear.black else Linear.transparent,
    );

    const linear_band = try image.band(Linear, linear_buffer, image.height, 0);

    const watchface = Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .hand_glow_falloff = config.hand_glow_falloff,
        .hand_length_falloff = config.hand_length_falloff,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .prism_glow_falloff = config.prism_glow_falloff,
        .prism_glow_color = Linear.init(0.1, config.prism_glow_linear_green, 1.0, 1.0),
        .rainbow_palette_id = if (dithering)
            config.dither_rainbow_palette_id
        else
            config.rainbow_palette_id,
    };

    watchface.render(linear_band, viewport, clock);

    const srgb_band = if (dithering) blk: {
        const dither = Dither{
            .normalized_strength = config.dither_normalized_strength,
            .normalized_chroma_emphasis = config.dither_normalized_chroma_emphasis,
            .palette = config.dither_palette_id.palette(),
        };

        break :blk try dither.apply(linear_band, srgb_buffer, dither_error_buffer.?);
    } else try linear_band.toSrgb(srgb_buffer);

    if (config.grain_enabled) {
        const grain = Grain{
            .normalized_deviation = config.grain_normalized_deviation,
            .dither_palette = if (dithering) config.dither_palette_id.palette() else null,
        };

        grain.apply(srgb_band);
    }

    if (config.background_enabled) {
        const crop = Crop{ .outside_color = Srgb.transparent, .antialias = !dithering };

        crop.apply(srgb_band, viewport);
    }

    return srgb_band;
}

const test_time = Time{ .total_minutes = 195.0 };
const test_size = 32;

test "render produces visible non-black output with defaults" {
    const config = try Config.init(std.testing.allocator);

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer, null);

    var sum: u64 = 0;

    for (band.buffer) |pixel| sum += @as(u64, pixel.r) + pixel.g + pixel.b;

    try std.testing.expect(sum > 0);
}

test "render quantizes to palette when dithering is enabled" {
    var config = try Config.init(std.testing.allocator);

    config.dither_enabled = true;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;
    var error_buffer: [test_size * Dither.Palette.color_count * 2]f32 = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer, &error_buffer);

    const palette = config.dither_palette_id.palette();

    for (band.buffer) |pixel| {
        if (pixel.a == 0) continue;

        var found = false;

        for (palette.srgb_colors) |color| {
            if (pixel.r == color.r and pixel.g == color.g and pixel.b == color.b) {
                found = true;
                break;
            }
        }

        try std.testing.expect(found);
    }
}

test "render ignores dithering when error buffer is null" {
    var dithered_config = try Config.init(std.testing.allocator);

    dithered_config.dither_enabled = true;

    var full_color_config = dithered_config;

    full_color_config.dither_enabled = false;

    const image = Image.init(test_size, test_size);

    // dither_enabled = true but no error buffer => forced full-color.
    var linear_forced: [test_size * test_size]Linear = undefined;
    var srgb_forced: [test_size * test_size]Srgb = undefined;

    const forced = try render(dithered_config, test_time, image, &linear_forced, &srgb_forced, null);

    // dither_enabled = false with an error buffer => also full-color.
    var linear_disabled: [test_size * test_size]Linear = undefined;
    var srgb_disabled: [test_size * test_size]Srgb = undefined;
    var error_buffer: [test_size * Dither.Palette.color_count * 2]f32 = undefined;

    const disabled =
        try render(full_color_config, test_time, image, &linear_disabled, &srgb_disabled, &error_buffer);

    try std.testing.expectEqualSlices(Srgb, disabled.buffer, forced.buffer);
}
