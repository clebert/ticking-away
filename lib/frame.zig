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
/// the resulting sRGB band. `srgb_buffer` must hold exactly `image.width *
/// image.height` pixels; `linear_buffer` must hold `image.width * image.height *
/// factor * factor` pixels, where `factor` is `supersampleFactor(config)`.
///
/// When `config.supersample_enabled` is set, geometry is rendered at `factor ×
/// factor` and box-averaged down in linear light before quantizing. The circle
/// boundary is antialiased separately by `Crop`.
///
/// `config.texture` selects one mutually-exclusive post-process (`.dither`,
/// `.grain`, `.none`). Dithering needs `dither_error_buffer` (>=
/// `dither.errorBufferSize(image.width)` f32); a `null` buffer falls back to
/// full-color output regardless of `config.texture`.
pub fn render(
    config: Config,
    time: Time,
    image: Image,
    linear_buffer: []Linear,
    srgb_buffer: []Srgb,
    dither_error_buffer: ?[]f32,
) !Image.Band(Srgb) {
    const clock = Clock.init(
        time,
        config.prism_normalized_size,
        config.rainbow_normalized_spread,
    );

    const viewport = image.viewport();
    const supersample = supersampleFactor(config);
    const supersampled = Image.init(image.width * supersample, image.height * supersample);

    @memset(
        linear_buffer,
        if (config.background_enabled) Linear.black else Linear.transparent,
    );

    const watchface = Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .prism_glow_color = Linear.init(0.1, config.prism_glow_linear_green, 1.0, 1.0),
        .rainbow_palette_id = config.rainbow_palette_id,
    };

    const supersampled_band = try supersampled.band(Linear, linear_buffer, supersampled.height, 0);

    watchface.render(supersampled_band, supersampled.viewport(), clock);

    if (supersample > 1) {
        downsample(linear_buffer, image.width, image.height, supersample);
    }

    const linear_band = try image.band(Linear, linear_buffer[0 .. image.width * image.height], image.height, 0);

    // Grain textures the 8-bit sRGB output, whereas dither replaces the sRGB
    // conversion entirely by quantizing the continuous linear image to the cube.
    const grain = Grain{ .normalized_deviation = config.grain_normalized_deviation };

    const dithering = config.texture == .dither and dither_error_buffer != null;

    const srgb_band = if (dithering)
        try dither.apply(linear_band, srgb_buffer, dither_error_buffer.?)
    else blk: {
        const continuous = try linear_band.toSrgb(srgb_buffer);

        if (config.texture == .grain) grain.apply(continuous);

        break :blk continuous;
    };

    if (config.background_enabled) {
        const crop = Crop{ .outside_color = Srgb.transparent, .antialias = true };

        crop.apply(srgb_band, viewport);
    }

    return srgb_band;
}

/// Supersample factor: 2 when `config.supersample_enabled`, else 1. Callers size
/// `linear_buffer` to `width * height * factor * factor`.
pub fn supersampleFactor(config: Config) usize {
    return if (config.supersample_enabled) 2 else 1;
}

/// Box-averages the supersampled image held in `buffer` down to `width * height`,
/// writing each averaged pixel into the front of the same buffer.
///
/// All four channels are averaged straight, including alpha. This is hue-correct
/// because the renderer accumulates each contribution premultiplied by its coverage
/// (colour scales with alpha), so averaging an edge pixel with a transparent neighbour
/// darkens its colour and alpha together rather than leaving a halo.
///
/// In-place is safe: destination pixel `i` reads the `factor * factor` source block
/// whose lowest index is `(i / width) * width * factor² + (i % width) * factor`,
/// which is always `>= i`. So no source pixel is overwritten before it is read, and
/// every source pixel is consumed by a destination at an index `<= its own`.
fn downsample(buffer: []Linear, width: usize, height: usize, factor: usize) void {
    const supersampled_width = width * factor;
    const inverse_sample_count: f32 = 1.0 / @as(f32, @floatFromInt(factor * factor));

    for (0..height) |y| {
        for (0..width) |x| {
            var sum: @Vector(4, f32) = .{ 0, 0, 0, 0 };

            for (0..factor) |subpixel_y| {
                const row = (y * factor + subpixel_y) * supersampled_width;

                for (0..factor) |subpixel_x| {
                    sum += buffer[row + x * factor + subpixel_x].vec;
                }
            }

            buffer[y * width + x] = .{ .vec = sum * @as(@Vector(4, f32), @splat(inverse_sample_count)) };
        }
    }
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

test "render quantizes to the cube when dithering is enabled" {
    var config = try Config.init(std.testing.allocator);

    config.texture = .dither;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;
    var error_buffer: [dither.errorBufferSize(test_size)]f32 = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer, &error_buffer);

    for (band.buffer) |pixel| {
        // The antialiased circle rim blends toward the transparent outside colour, so
        // only fully-opaque interior pixels are guaranteed to be exact cube colours.
        if (pixel.a != 255) continue;

        try std.testing.expect(dither.isCubeChannel(pixel.r));
        try std.testing.expect(dither.isCubeChannel(pixel.g));
        try std.testing.expect(dither.isCubeChannel(pixel.b));
    }
}

test "render leaves the output full-color when dithering is disabled" {
    var config = try Config.init(std.testing.allocator);

    config.texture = .none;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer, null);

    // A continuous rainbow render keeps off-cube channels, so assert at least one
    // pixel is genuinely full-color (otherwise dither/non-dither are indistinguishable).
    var has_off_cube = false;

    for (band.buffer) |pixel| {
        if (!dither.isCubeChannel(pixel.r) or !dither.isCubeChannel(pixel.g) or !dither.isCubeChannel(pixel.b)) {
            has_off_cube = true;
            break;
        }
    }

    try std.testing.expect(has_off_cube);
}

test "render perturbs the sRGB output when texture is grain" {
    var config = try Config.init(std.testing.allocator);

    config.grain_normalized_deviation = 0.1;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var plain_buffer: [test_size * test_size]Srgb = undefined;
    var grain_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);

    config.texture = .none;

    const plain = try render(config, test_time, image, &linear_buffer, &plain_buffer, null);

    config.texture = .grain;

    const grained = try render(config, test_time, image, &linear_buffer, &grain_buffer, null);

    // The only difference between the two renders is the grain pass, so any divergence
    // proves the texture == .grain branch actually applies it.
    var differs = false;

    for (plain.buffer, grained.buffer) |a, b| {
        if (a.r != b.r or a.g != b.g or a.b != b.b) {
            differs = true;
            break;
        }
    }

    try std.testing.expect(differs);
}

test "downsample averages each source block in place" {
    // 4x4 source -> 2x2 target (factor 2). Each pixel's channels carry its flat index,
    // so a block average is just the mean of its four source indices.
    var buffer: [16]Linear = undefined;

    for (0..16) |i| {
        const value: f32 = @floatFromInt(i);

        buffer[i] = Linear.init(value, value, value, value);
    }

    downsample(&buffer, 2, 2, 2);

    const expected = [_]f32{ 2.5, 4.5, 10.5, 12.5 };

    for (expected, 0..) |mean, i| {
        try std.testing.expectApproxEqAbs(mean, buffer[i].vec[0], 1e-6);
    }
}

test "render with supersampling changes edge pixels" {
    var config = try Config.init(std.testing.allocator);

    config.texture = .none;
    config.supersample_enabled = false;

    const image = Image.init(test_size, test_size);

    var plain_linear: [test_size * test_size]Linear = undefined;
    var plain_srgb: [test_size * test_size]Srgb = undefined;

    const plain = try render(config, test_time, image, &plain_linear, &plain_srgb, null);
    const plain_copy = plain.buffer[0 .. test_size * test_size].*;

    config.supersample_enabled = true;

    var supersampled_linear: [test_size * test_size * 4]Linear = undefined;
    var supersampled_srgb: [test_size * test_size]Srgb = undefined;

    const supersampled = try render(config, test_time, image, &supersampled_linear, &supersampled_srgb, null);

    // Antialiasing softens the hard prism/hand/circle edges, so the two frames must
    // differ somewhere even though the geometry is identical.
    var differs = false;

    for (plain_copy, supersampled.buffer) |a, b| {
        if (a.r != b.r or a.g != b.g or a.b != b.b or a.a != b.a) {
            differs = true;
            break;
        }
    }

    try std.testing.expect(differs);
}
