const std = @import("std");

const Clock = @import("Clock.zig");
const Config = @import("Config.zig");
const Crop = @import("Crop.zig");
const dither = @import("dither/root.zig");
const Grain = @import("Grain.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Rainbow = @import("Rainbow.zig");
const Srgb = @import("Srgb.zig");
const Time = @import("Time.zig");
const Watchface = @import("Watchface.zig");

/// Renders a whole watchface frame in one band; see `renderBand`.
pub fn render(
    config: *const Config,
    time: Time,
    image: Image,
    linear_buffer: []Linear,
    srgb_buffer: []Srgb,
    dither_error_buffer: ?[]f32,
) !Image.Band(Srgb) {
    return renderBand(
        config,
        time,
        image,
        image.height,
        0,
        linear_buffer,
        srgb_buffer,
        dither_error_buffer,
    );
}

/// Renders strip `band_index` (height `band_height`) of the watchface from
/// `config` into `srgb_buffer` and returns the resulting sRGB band.
/// `srgb_buffer` and `linear_buffer` must each hold exactly
/// `image.width * band_height` pixels.
///
/// Geometry is drawn with analytic coverage antialiasing; the circle boundary is
/// antialiased separately by `Crop`.
///
/// `config.texture` selects one mutually-exclusive post-process
/// (`.dither_pebble`, `.dither_trmnl`, `.grain`, `.none`). Both dithers need
/// `dither_error_buffer` (>= the active module's `errorBufferSize(image.width)`
/// f32; size it for `dither.pebble`, the larger, when the texture can change at
/// runtime); a `null` buffer falls back to full-color output regardless of
/// `config.texture`. The dither carries error forward between bands, so strips
/// must be rendered in increasing `band_index` order with the same
/// `dither_error_buffer` (it is zeroed on `band_index` 0).
pub fn renderBand(
    config: *const Config,
    time: Time,
    image: Image,
    band_height: usize,
    band_index: usize,
    linear_buffer: []Linear,
    srgb_buffer: []Srgb,
    dither_error_buffer: ?[]f32,
) !Image.Band(Srgb) {
    const rainbow = Rainbow.get(config.rainbow_style);

    const clock = Clock.init(time, .{
        .prism_normalized_size = config.prism_normalized_size,
        .rainbow_normalized_spread = config.rainbow_normalized_spread,
        .color_count = rainbow.len,
    });

    const viewport = image.viewport();

    @memset(
        linear_buffer,
        if (config.background_enabled) Linear.black else Linear.transparent,
    );

    const watchface = Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .rainbow = rainbow,
    };

    const linear_band = try image.band(Linear, linear_buffer, band_height, band_index);

    watchface.render(linear_band, viewport, &clock);

    // Grain textures the 8-bit sRGB output, whereas the dithers replace the sRGB
    // conversion entirely: dither.pebble quantizes to the 64-colour cube,
    // dither.trmnl to the e-ink panel's four greyscale levels.
    const grain = Grain{ .normalized_deviation = config.grain_normalized_deviation };

    const srgb_band = blk: {
        if (dither_error_buffer != null) {
            switch (config.texture) {
                .dither_pebble => break :blk try dither.pebble.apply(
                    linear_band,
                    srgb_buffer,
                    dither_error_buffer.?,
                ),
                .dither_trmnl => break :blk try dither.trmnl.apply(
                    linear_band,
                    srgb_buffer,
                    dither_error_buffer.?,
                ),
                else => {},
            }
        }

        const continuous = try linear_band.toSrgb(srgb_buffer);

        if (config.texture == .grain) grain.apply(continuous, viewport, &clock.prism);

        break :blk continuous;
    };

    if (config.background_enabled) {
        const crop = Crop{ .outside_color = Srgb.transparent, .antialias = true };

        crop.apply(srgb_band, viewport);
    }

    return srgb_band;
}

const test_time = Time{ .total_minutes = 195.0 };
const test_size = 32;

test "render produces visible non-black output with defaults" {
    const config = Config.default;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(&config, test_time, image, &linear_buffer, &srgb_buffer, null);

    var sum: u64 = 0;

    for (band.buffer) |pixel| sum += @as(u64, pixel.r) + pixel.g + pixel.b;

    try std.testing.expect(sum > 0);
}

test "render quantizes to the cube when pebble dithering is enabled" {
    var config = Config.default;

    config.texture = .dither_pebble;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;
    var error_buffer: [dither.pebble.errorBufferSize(test_size)]f32 = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(&config, test_time, image, &linear_buffer, &srgb_buffer, &error_buffer);

    for (band.buffer) |pixel| {
        // The antialiased circle rim blends toward the transparent outside colour, so
        // only fully-opaque interior pixels are guaranteed to be exact cube colours.
        if (pixel.a != 255) continue;

        try std.testing.expect(dither.pebble.isCubeChannel(pixel.r));
        try std.testing.expect(dither.pebble.isCubeChannel(pixel.g));
        try std.testing.expect(dither.pebble.isCubeChannel(pixel.b));
    }
}

test "render quantizes to neutral greys when trmnl dithering is enabled" {
    var config = Config.default;

    config.texture = .dither_trmnl;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;
    var error_buffer: [dither.trmnl.errorBufferSize(test_size)]f32 = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(&config, test_time, image, &linear_buffer, &srgb_buffer, &error_buffer);

    for (band.buffer) |pixel| {
        // Only fully-opaque interior pixels are guaranteed exact grey levels; the
        // antialiased rim blends toward the transparent outside colour.
        if (pixel.a != 255) continue;

        try std.testing.expect(dither.trmnl.isGreyLevel(pixel.r));
        try std.testing.expectEqual(pixel.r, pixel.g);
        try std.testing.expectEqual(pixel.r, pixel.b);
    }
}

test "render leaves the output full-color when dithering is disabled" {
    var config = Config.default;

    config.texture = .none;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);
    const band = try render(&config, test_time, image, &linear_buffer, &srgb_buffer, null);

    // A continuous rainbow render keeps off-cube channels, so assert at least one
    // pixel is genuinely full-color (otherwise dither/non-dither are indistinguishable).
    var has_off_cube = false;

    for (band.buffer) |pixel| {
        if (!dither.pebble.isCubeChannel(pixel.r) or
            !dither.pebble.isCubeChannel(pixel.g) or
            !dither.pebble.isCubeChannel(pixel.b))
        {
            has_off_cube = true;
            break;
        }
    }

    try std.testing.expect(has_off_cube);
}

test "render perturbs the sRGB output when texture is grain" {
    var config = Config.default;

    config.grain_normalized_deviation = 0.1;

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var plain_buffer: [test_size * test_size]Srgb = undefined;
    var grain_buffer: [test_size * test_size]Srgb = undefined;

    const image = Image.init(test_size, test_size);

    config.texture = .none;

    const plain = try render(&config, test_time, image, &linear_buffer, &plain_buffer, null);

    config.texture = .grain;

    const grained = try render(&config, test_time, image, &linear_buffer, &grain_buffer, null);

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
    var config = Config.default;

    config.texture = .dither_pebble;

    const image = Image.init(test_size, test_size);

    var reference_linear: [test_size * test_size]Linear = undefined;
    var reference_srgb: [test_size * test_size]Srgb = undefined;
    var reference_error: [dither.pebble.errorBufferSize(test_size)]f32 = undefined;

    const reference = try render(
        &config,
        test_time,
        image,
        &reference_linear,
        &reference_srgb,
        &reference_error,
    );
    const reference_copy = reference.buffer[0 .. test_size * test_size].*;

    const band_height = 1;

    var band_linear: [test_size * band_height]Linear = undefined;
    var band_srgb: [test_size * band_height]Srgb = undefined;
    var band_error: [dither.pebble.errorBufferSize(test_size)]f32 = undefined;
    var banded: [test_size * test_size]Srgb = undefined;

    for (0..@divExact(test_size, band_height)) |band_index| {
        const strip = try renderBand(
            &config,
            test_time,
            image,
            band_height,
            band_index,
            &band_linear,
            &band_srgb,
            &band_error,
        );

        @memcpy(
            banded[band_index * band_height * test_size ..][0 .. band_height * test_size],
            strip.buffer,
        );
    }

    try std.testing.expectEqualSlices(Srgb, &reference_copy, &banded);
}

test "render antialiases the circle rim" {
    var config = Config.default;

    config.texture = .none;
    config.background_enabled = true;

    const image = Image.init(test_size, test_size);

    var linear_buffer: [test_size * test_size]Linear = undefined;
    var srgb_buffer: [test_size * test_size]Srgb = undefined;

    const band = try render(&config, test_time, image, &linear_buffer, &srgb_buffer, null);

    // With the background enabled, Crop feathers the disc boundary: at least one pixel
    // must be partially transparent, neither the transparent outside nor the fully opaque
    // interior. (Ray-edge coverage is exercised by Glow's renderLine feather test.)
    var found_partial_alpha = false;

    for (band.buffer) |pixel| {
        if (pixel.a > 0 and pixel.a < 255) {
            found_partial_alpha = true;
            break;
        }
    }

    try std.testing.expect(found_partial_alpha);
}
