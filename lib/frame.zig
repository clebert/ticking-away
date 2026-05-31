const std = @import("std");

const Clock = @import("Clock.zig");
const Config = @import("Config.zig");
const Crop = @import("Crop.zig");
const dither = @import("dither.zig");
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
/// When `config.dither_enabled` is true the output is quantized to the Pebble cube
/// with ordered blue-noise dithering; otherwise full-color sRGB is emitted.
pub fn render(
    config: Config,
    time: Time,
    image: Image,
    linear_buffer: []Linear,
    srgb_buffer: []Srgb,
) !Image.Band(Srgb) {
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
        .rainbow_palette_id = config.rainbow_palette_id,
    };

    watchface.render(linear_band, viewport, clock);

    // Grain is a full-color analog texture. When dithering it runs on the continuous
    // image before quantization so it is dithered along with the image (and so its
    // shadow-suppressed jitter never snaps to a neighbouring cube level); otherwise
    // it runs on the full-color output directly.
    const grain = Grain{ .normalized_deviation = config.grain_normalized_deviation };

    const srgb_band = if (config.dither_enabled) blk: {
        if (config.grain_enabled) grain.applyLinear(linear_band);

        break :blk try dither.apply(linear_band, srgb_buffer);
    } else blk: {
        const continuous = try linear_band.toSrgb(srgb_buffer);

        if (config.grain_enabled) grain.apply(continuous);

        break :blk continuous;
    };

    if (config.background_enabled) {
        const crop = Crop{ .outside_color = Srgb.transparent, .antialias = !config.dither_enabled };

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
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer);

    var sum: u64 = 0;

    for (band.buffer) |pixel| sum += @as(u64, pixel.r) + pixel.g + pixel.b;

    try std.testing.expect(sum > 0);
}

test "render quantizes to the cube when dithering is enabled" {
    var config = try Config.init(std.testing.allocator);

    config.dither_enabled = true;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer);

    for (band.buffer) |pixel| {
        if (pixel.a == 0) continue;

        try std.testing.expect(dither.isCubeChannel(pixel.r));
        try std.testing.expect(dither.isCubeChannel(pixel.g));
        try std.testing.expect(dither.isCubeChannel(pixel.b));
    }
}

test "render leaves the output full-color when dithering is disabled" {
    var config = try Config.init(std.testing.allocator);

    config.dither_enabled = false;
    config.grain_enabled = false;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer);

    // A continuous render of the rainbow keeps off-cube channel values; if every pixel
    // happened to land on a cube level the dither and non-dither paths would be
    // indistinguishable, so assert at least one pixel is genuinely full-color.
    var has_off_cube = false;

    for (band.buffer) |pixel| {
        if (!dither.isCubeChannel(pixel.r) or !dither.isCubeChannel(pixel.g) or !dither.isCubeChannel(pixel.b)) {
            has_off_cube = true;
            break;
        }
    }

    try std.testing.expect(has_off_cube);
}
