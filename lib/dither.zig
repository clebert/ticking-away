//! Ordered blue-noise dithering to the 64-colour Pebble cube (every channel in
//! {0, 85, 170, 255}). Each channel is independently rounded to the nearest cube
//! level after a shared per-pixel blue-noise threshold offset.
//!
//! The dither is purely local — no error diffusion and no cross-band state — so
//! bands render independently (the threshold depends only on the absolute pixel
//! position) and the output can never drift into an off-hue cube colour. Blue
//! noise spreads the sparse dots of the fade-to-black evenly, which is the
//! smoothest gradient the four-level cube allows. The threshold tile is generated
//! offline and embedded at build time; see tools/blue_noise_generator.zig.

const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

// Square void-and-cluster blue-noise threshold tile, one byte per pixel. Regenerate with:
// zig run tools/blue_noise_generator.zig
const tile = @embedFile("blue_noise.bin");
const tile_size = blk: {
    var n: usize = 1;

    while (n * n < tile.len) n += 1;

    break :blk n;
};

comptime {
    std.debug.assert(tile_size * tile_size == tile.len);

    // apply()'s black fast-path relies on a pure-black pixel rounding to cube level 0 for every
    // threshold, which holds only while |threshold| < 0.5. The tile's extreme thresholds are at
    // bytes 0 and 255; assert both stay inside the bound so a future change to thresholdFromByte
    // cannot silently desync the fast-path from the general path.
    std.debug.assert(@abs(thresholdFromByte(0)) < 0.5 and @abs(thresholdFromByte(255)) < 0.5);
}

// The cube's four levels are spaced 85 sRGB units apart: 0, 85, 170, 255.
const level_step = 85.0;
const max_level = 3.0;

pub fn apply(band: Image.Band(Linear), srgb_buffer: []Srgb) !Image.Band(Srgb) {
    const width = band.width;
    const height = band.bandHeight();

    if (srgb_buffer.len != band.buffer.len) return error.BufferSizeMismatch;

    for (0..height) |y| {
        const threshold_y = band.imageY(y);

        for (0..width) |x| {
            const linear = band.colorAt(x, y).*;
            const alpha = Srgb.clampedByte(linear.vec[3] * 255.0);

            // Fast-path the black background, which dominates the frame: it quantizes to
            // cube black for every threshold, so skip the three per-channel gamma encodes.
            if (linear.vec[0] == 0 and linear.vec[1] == 0 and linear.vec[2] == 0) {
                srgb_buffer[y * width + x] = .{ .r = 0, .g = 0, .b = 0, .a = alpha };
                continue;
            }

            const threshold = thresholdAt(x, threshold_y);

            srgb_buffer[y * width + x] = .{
                .r = quantizeChannel(linear.vec[0], threshold),
                .g = quantizeChannel(linear.vec[1], threshold),
                .b = quantizeChannel(linear.vec[2], threshold),
                .a = alpha,
            };
        }
    }

    return .{ .buffer = srgb_buffer, .width = width, .y_offset = band.y_offset };
}

/// Rounds one linear-light channel to a cube level after offsetting by the pixel's
/// blue-noise threshold, in the gamma-encoded sRGB domain where the levels are
/// evenly spaced.
fn quantizeChannel(linear_value: f32, threshold: f32) u8 {
    const encoded = Linear.linearToSrgbComponent(linear_value) * 255.0;
    const level = std.math.clamp(
        @round((encoded + threshold * level_step) / level_step),
        0.0,
        max_level,
    );

    return @intFromFloat(level * level_step);
}

/// The pixel's blue-noise threshold, sampled from the build-time threshold tile.
fn thresholdAt(x: usize, image_y: usize) f32 {
    return thresholdFromByte(tile[(image_y % tile_size) * tile_size + (x % tile_size)]);
}

/// Maps a stored tile byte to a threshold in (-0.5, 0.5), symmetric about 0: the rank index
/// centred on its bucket midpoint so the rounding stays unbiased.
fn thresholdFromByte(value: u8) f32 {
    return (@as(f32, @floatFromInt(value)) + 0.5) / 256.0 - 0.5;
}

pub fn isCubeChannel(channel: u8) bool {
    return channel == 0 or channel == 85 or channel == 170 or channel == 255;
}

test "apply quantizes every channel to a cube level" {
    const image = Image.init(8, 8);
    const pixel_count = 8 * 8;

    var linear_buffer: [pixel_count]Linear = undefined;

    for (0..8) |y| {
        for (0..8) |x| {
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);

            linear_buffer[y * 8 + x] = Linear.init(fx / 7.0, fy / 7.0, 0.42, 1.0);
        }
    }

    var srgb_buffer: [pixel_count]Srgb = undefined;

    const band = try image.band(Linear, &linear_buffer, 8, 0);
    const result = try apply(band, &srgb_buffer);

    for (result.buffer) |pixel| {
        try std.testing.expect(isCubeChannel(pixel.r));
        try std.testing.expect(isCubeChannel(pixel.g));
        try std.testing.expect(isCubeChannel(pixel.b));
    }
}

test "apply preserves alpha" {
    const image = Image.init(2, 2);

    var linear_buffer = [_]Linear{Linear.init(0.5, 0.5, 0.5, 0.75)} ** 4;
    var srgb_buffer: [4]Srgb = undefined;

    const band = try image.band(Linear, &linear_buffer, 2, 0);
    const result = try apply(band, &srgb_buffer);

    for (result.buffer) |pixel| {
        try std.testing.expectEqual(@as(u8, 191), pixel.a);
    }
}

test "apply maps pure black to cube black" {
    const image = Image.init(4, 4);

    var linear_buffer = [_]Linear{Linear.black} ** 16;
    var srgb_buffer: [16]Srgb = undefined;

    const band = try image.band(Linear, &linear_buffer, 4, 0);
    const result = try apply(band, &srgb_buffer);

    for (result.buffer) |pixel| {
        try std.testing.expectEqual(@as(u8, 0), pixel.r);
        try std.testing.expectEqual(@as(u8, 0), pixel.g);
        try std.testing.expectEqual(@as(u8, 0), pixel.b);
    }
}

test "apply dithers a between-levels mid-tone to more than one level" {
    const width = 32;
    const height = 32;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    // sRGB ~42 sits halfway between cube levels 0 and 85, so the blue-noise threshold
    // must split the field between the two rather than snapping it all one way.
    const mid = Srgb.srgbToLinearComponent(42.0 / 255.0);

    var linear_buffer = [_]Linear{Linear.init(mid, mid, mid, 1.0)} ** pixel_count;
    var srgb_buffer: [pixel_count]Srgb = undefined;

    const band = try image.band(Linear, &linear_buffer, height, 0);
    const result = try apply(band, &srgb_buffer);

    var has_low = false;
    var has_high = false;

    for (result.buffer) |pixel| {
        if (pixel.r == 0) has_low = true;
        if (pixel.r == 85) has_high = true;
    }

    try std.testing.expect(has_low and has_high);
}

test "multi-band apply matches single-band apply" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    var linear_buffer: [pixel_count]Linear = undefined;

    for (0..height) |y| {
        const t: f32 = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));

        for (0..width) |x| {
            linear_buffer[y * width + x] = Linear.init(t * 0.8, t * 0.3, (1.0 - t) * 0.5, 1.0);
        }
    }

    var reference: [pixel_count]Srgb = undefined;

    const full_band = try image.band(Linear, &linear_buffer, height, 0);

    _ = try apply(full_band, &reference);

    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output: [pixel_count]Srgb = undefined;
        var band_srgb_buffer: [pixel_count]Srgb = undefined;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;
            const band_linear = linear_buffer[row_start..][0..band_pixels];
            const narrow_band = try image.band(Linear, band_linear, band_height, band_index);

            const srgb_band = try apply(narrow_band, band_srgb_buffer[0..band_pixels]);

            @memcpy(banded_output[row_start..][0..band_pixels], srgb_band.buffer);
        }

        try std.testing.expectEqualSlices(Srgb, &reference, &banded_output);
    }
}
