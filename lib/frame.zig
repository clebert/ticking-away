const std = @import("std");

const Clock = @import("Clock.zig");
const Config = @import("Config.zig");
const Crop = @import("Crop.zig");
const dither_pebble = @import("dither_pebble.zig");
const dither_trmnl = @import("dither_trmnl.zig");
const Grain = @import("Grain.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");
const Time = @import("Time.zig");
const Watchface = @import("Watchface.zig");

/// Renders a whole watchface frame in one band; see `renderBand`.
pub fn render(
    config: Config,
    time: Time,
    image: Image,
    linear_buffer: []Linear,
    srgb_buffer: []Srgb,
    dither_error_buffer: ?[]f32,
) !Image.Band(Srgb) {
    return renderBand(config, time, image, image.height, 0, linear_buffer, srgb_buffer, dither_error_buffer);
}

/// Renders strip `band_index` (height `band_height`) of the watchface from
/// `config` into `srgb_buffer` and returns the resulting sRGB band.
/// `srgb_buffer` must hold exactly `image.width * band_height` pixels;
/// `linear_buffer` must hold `image.width * band_height * factor * factor`
/// pixels, where `factor` is `supersampleFactor(config)`.
///
/// When `config.supersample_enabled` is set, geometry is rendered at `factor ×
/// factor` and box-averaged down in linear light before quantizing. The circle
/// boundary is antialiased separately by `Crop`.
///
/// `config.texture` selects one mutually-exclusive post-process
/// (`.dither_pebble`, `.dither_trmnl`, `.grain`, `.none`). Both dithers need
/// `dither_error_buffer` (>= the active module's `errorBufferSize(image.width)`
/// f32; size it for `dither_pebble`, the larger, when the texture can change at
/// runtime); a `null` buffer falls back to full-color output regardless of
/// `config.texture`. The dither carries error forward between bands, so strips
/// must be rendered in increasing `band_index` order with the same
/// `dither_error_buffer` (it is zeroed on `band_index` 0).
pub fn renderBand(
    config: Config,
    time: Time,
    image: Image,
    band_height: usize,
    band_index: usize,
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

    const supersampled_band = try supersampled.band(Linear, linear_buffer, band_height * supersample, band_index);

    watchface.render(supersampled_band, supersampled.viewport(), clock);

    if (supersample > 1) {
        downsample(linear_buffer, image.width, band_height, supersample);
    }

    const linear_band = try image.band(Linear, linear_buffer[0 .. image.width * band_height], band_height, band_index);

    // Grain textures the 8-bit sRGB output, whereas the dithers replace the sRGB
    // conversion entirely: dither_pebble quantizes to the 64-colour cube,
    // dither_trmnl to the e-ink panel's four greyscale levels.
    const grain = Grain{ .normalized_deviation = config.grain_normalized_deviation };

    const srgb_band = blk: {
        if (dither_error_buffer != null) {
            switch (config.texture) {
                .dither_pebble => break :blk try dither_pebble.apply(linear_band, srgb_buffer, dither_error_buffer.?),
                .dither_trmnl => break :blk try dither_trmnl.apply(linear_band, srgb_buffer, dither_error_buffer.?),
                else => {},
            }
        }

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

test "render quantizes to the cube when pebble dithering is enabled" {
    var config = try Config.init(std.testing.allocator);

    config.texture = .dither_pebble;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;
    var error_buffer: [dither_pebble.errorBufferSize(test_size)]f32 = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer, &error_buffer);

    for (band.buffer) |pixel| {
        // The antialiased circle rim blends toward the transparent outside colour, so
        // only fully-opaque interior pixels are guaranteed to be exact cube colours.
        if (pixel.a != 255) continue;

        try std.testing.expect(dither_pebble.isCubeChannel(pixel.r));
        try std.testing.expect(dither_pebble.isCubeChannel(pixel.g));
        try std.testing.expect(dither_pebble.isCubeChannel(pixel.b));
    }
}

test "render quantizes to neutral greys when trmnl dithering is enabled" {
    var config = try Config.init(std.testing.allocator);

    config.texture = .dither_trmnl;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;
    var error_buffer: [dither_trmnl.errorBufferSize(test_size)]f32 = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(config, test_time, image, &linear_buffer, &srgb_buffer, &error_buffer);

    for (band.buffer) |pixel| {
        // Only fully-opaque interior pixels are guaranteed exact grey levels; the
        // antialiased rim blends toward the transparent outside colour.
        if (pixel.a != 255) continue;

        try std.testing.expect(dither_trmnl.isGreyLevel(pixel.r));
        try std.testing.expectEqual(pixel.r, pixel.g);
        try std.testing.expectEqual(pixel.r, pixel.b);
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
        if (!dither_pebble.isCubeChannel(pixel.r) or !dither_pebble.isCubeChannel(pixel.g) or !dither_pebble.isCubeChannel(pixel.b)) {
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

test "renderBand strip-by-strip matches a single full-height render" {
    var config = try Config.init(std.testing.allocator);

    config.texture = .dither_pebble;
    config.supersample_enabled = true;

    const image = Image.init(test_size, test_size);

    var reference_linear: [test_size * test_size * 4]Linear = undefined;
    var reference_srgb: [test_size * test_size]Srgb = undefined;
    var reference_error: [dither_pebble.errorBufferSize(test_size)]f32 = undefined;

    const reference = try render(config, test_time, image, &reference_linear, &reference_srgb, &reference_error);
    const reference_copy = reference.buffer[0 .. test_size * test_size].*;

    const band_height = 1;

    var band_linear: [test_size * band_height * 4]Linear = undefined;
    var band_srgb: [test_size * band_height]Srgb = undefined;
    var band_error: [dither_pebble.errorBufferSize(test_size)]f32 = undefined;
    var banded: [test_size * test_size]Srgb = undefined;

    for (0..test_size / band_height) |band_index| {
        const strip = try renderBand(config, test_time, image, band_height, band_index, &band_linear, &band_srgb, &band_error);

        @memcpy(banded[band_index * band_height * test_size ..][0 .. band_height * test_size], strip.buffer);
    }

    try std.testing.expectEqualSlices(Srgb, &reference_copy, &banded);
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
