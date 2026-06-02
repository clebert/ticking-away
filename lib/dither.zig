//! Floyd–Steinberg error-diffusion dithering to the 64-colour Pebble cube (every
//! channel in {0, 85, 170, 255}). Channels are quantized in the gamma-encoded
//! sRGB domain (cube levels evenly spaced 85 apart) and rounding error is
//! diffused with the standard 7/3/5/1 weights along a serpentine scan.
//!
//! The only state is a two-row error buffer the caller owns and sizes with
//! `errorBufferSize(width)`. Pending row errors are carried forward between bands,
//! so a frame can be dithered in a single full-height call or streamed
//! strip-by-strip — the buffer is zeroed on the first band (`y_offset == 0`) and
//! left with the invariant "pending errors in row 0, row 1 clean" between calls.
//! Diffusion runs top-to-bottom, so bands must be applied in increasing y order.

const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

const channels = 3;

// The cube's four levels are spaced 85 sRGB units apart: 0, 85, 170, 255.
const level_step = 85.0;
const max_level = 3.0;

/// f32 count for `apply`'s two-row error buffer.
pub fn errorBufferSize(width: usize) usize {
    return width * channels * 2;
}

pub fn apply(
    band: Image.Band(Linear),
    srgb_buffer: []Srgb,
    error_buffer: []f32,
) !Image.Band(Srgb) {
    const width = band.width;
    const height = band.bandHeight();

    if (srgb_buffer.len != band.buffer.len) return error.BufferSizeMismatch;

    const stride = width * channels;

    if (error_buffer.len < stride * 2) return error.BufferSizeMismatch;

    // Zero both rows on the first band; later bands inherit pending errors in row 0.
    if (band.y_offset == 0) {
        @memset(error_buffer[0 .. stride * 2], 0);
    }

    var current_row_index: usize = 0;

    for (0..height) |y| {
        const right_to_left = (band.imageY(y) % 2) == 1;
        const current = error_buffer[current_row_index * stride ..][0..stride];
        const next = error_buffer[(1 - current_row_index) * stride ..][0..stride];

        for (0..width) |scan_index| {
            const x = if (right_to_left) width - 1 - scan_index else scan_index;

            const linear = band.colorAt(x, y).*;
            const alpha = Srgb.clampedByte(linear.vec[3] * 255.0);
            const error_offset = x * channels;

            // The black background dominates the frame and must not accrue a diffused
            // halo, so quantize it straight to cube black and diffuse nothing.
            if (linear.vec[0] == 0 and linear.vec[1] == 0 and linear.vec[2] == 0) {
                srgb_buffer[y * width + x] = .{ .r = 0, .g = 0, .b = 0, .a = alpha };
                continue;
            }

            var quantized: [channels]u8 = undefined;
            var quantization_error: [channels]f32 = undefined;

            inline for (0..channels) |channel| {
                const encoded = Linear.linearToSrgbComponent(linear.vec[channel]) * 255.0;
                const adjusted = encoded + current[error_offset + channel];
                const level = std.math.clamp(@round(adjusted / level_step), 0.0, max_level);
                const value = level * level_step;

                quantized[channel] = @intFromFloat(value);
                quantization_error[channel] = adjusted - value;
            }

            srgb_buffer[y * width + x] = .{
                .r = quantized[0],
                .g = quantized[1],
                .b = quantized[2],
                .a = alpha,
            };

            const ahead_valid = if (right_to_left) x > 0 else x + 1 < width;
            const behind_valid = if (right_to_left) x + 1 < width else x > 0;

            if (ahead_valid) {
                const ahead_offset = (if (right_to_left) x - 1 else x + 1) * channels;

                inline for (0..channels) |channel| {
                    current[ahead_offset + channel] += quantization_error[channel] * (7.0 / 16.0);
                    next[ahead_offset + channel] += quantization_error[channel] * (1.0 / 16.0);
                }
            }

            if (behind_valid) {
                const behind_offset = (if (right_to_left) x + 1 else x - 1) * channels;

                inline for (0..channels) |channel| {
                    next[behind_offset + channel] += quantization_error[channel] * (3.0 / 16.0);
                }
            }

            inline for (0..channels) |channel| {
                next[error_offset + channel] += quantization_error[channel] * (5.0 / 16.0);
            }
        }

        @memset(current, 0);

        current_row_index = 1 - current_row_index;
    }

    // Restore the invariant (pending errors in row 0) after an odd-height band.
    if (current_row_index != 0) {
        @memcpy(error_buffer[0..stride], error_buffer[stride..][0..stride]);
        @memset(error_buffer[stride..][0..stride], 0);
    }

    return .{ .buffer = srgb_buffer, .width = width, .y_offset = band.y_offset };
}

pub fn isCubeChannel(channel: u8) bool {
    return channel == 0 or channel == 85 or channel == 170 or channel == 255;
}

test "errorBufferSize covers two rows of per-channel error" {
    try std.testing.expectEqual(@as(usize, 10 * 3 * 2), errorBufferSize(10));
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
    var error_buffer: [errorBufferSize(8)]f32 = undefined;

    const band = try image.band(Linear, &linear_buffer, 8, 0);
    const result = try apply(band, &srgb_buffer, &error_buffer);

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
    var error_buffer: [errorBufferSize(2)]f32 = undefined;

    const band = try image.band(Linear, &linear_buffer, 2, 0);
    const result = try apply(band, &srgb_buffer, &error_buffer);

    for (result.buffer) |pixel| {
        try std.testing.expectEqual(@as(u8, 191), pixel.a);
    }
}

test "apply maps pure black to cube black" {
    const image = Image.init(4, 4);

    var linear_buffer = [_]Linear{Linear.black} ** 16;
    var srgb_buffer: [16]Srgb = undefined;
    var error_buffer: [errorBufferSize(4)]f32 = undefined;

    const band = try image.band(Linear, &linear_buffer, 4, 0);
    const result = try apply(band, &srgb_buffer, &error_buffer);

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

    // sRGB ~42 sits halfway between cube levels 0 and 85, so error diffusion must
    // split the field between the two rather than snapping it all one way.
    const mid = Srgb.srgbToLinearComponent(42.0 / 255.0);

    var linear_buffer = [_]Linear{Linear.init(mid, mid, mid, 1.0)} ** pixel_count;
    var srgb_buffer: [pixel_count]Srgb = undefined;
    var error_buffer: [errorBufferSize(width)]f32 = undefined;

    const band = try image.band(Linear, &linear_buffer, height, 0);
    const result = try apply(band, &srgb_buffer, &error_buffer);

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
            // Rows 16-31 are pure black so a band seam lands inside the fast-path region,
            // exercising that its error-drop is band-invariant.
            linear_buffer[y * width + x] = if (y >= 16 and y < 32)
                Linear.black
            else
                Linear.init(t * 0.8, t * 0.3, (1.0 - t) * 0.5, 1.0);
        }
    }

    var reference: [pixel_count]Srgb = undefined;
    var reference_error: [errorBufferSize(width)]f32 = undefined;

    const full_band = try image.band(Linear, &linear_buffer, height, 0);

    _ = try apply(full_band, &reference, &reference_error);

    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output: [pixel_count]Srgb = undefined;
        var band_srgb_buffer: [pixel_count]Srgb = undefined;
        var band_error: [errorBufferSize(width)]f32 = undefined;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;
            const band_linear = linear_buffer[row_start..][0..band_pixels];
            const narrow_band = try image.band(Linear, band_linear, band_height, band_index);

            const srgb_band = try apply(narrow_band, band_srgb_buffer[0..band_pixels], &band_error);

            @memcpy(banded_output[row_start..][0..band_pixels], srgb_band.buffer);
        }

        try std.testing.expectEqualSlices(Srgb, &reference, &banded_output);
    }
}
