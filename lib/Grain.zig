const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

/// Maximum per-pixel deviation as a fraction of the sRGB range (0.0–1.0).
/// At 1.0, each pixel can shift by up to ±255 sRGB units.
normalized_deviation: f32,

/// Adds film-like grain to a full-color sRGB band: a uniform per-pixel
/// luminance jitter applied directly to the 8-bit output.
pub fn apply(self: Self, band: Image.Band(Srgb)) void {
    std.debug.assert(self.normalized_deviation >= 0.0 and self.normalized_deviation <= 1.0);

    if (self.normalized_deviation == 0.0) return;

    // ×255×2 maps deviation 1.0 to a full ±255 swing.
    const strength = self.normalized_deviation * 255.0 * 2.0;

    for (0..band.bandHeight()) |local_y| {
        const image_y = band.imageY(local_y);
        const row = band.buffer[local_y * band.width ..][0..band.width];

        for (row, 0..) |*srgb, x| {
            // Leave pure black untextured so the dark background stays clean
            // instead of being speckled with grain.
            if (srgb.r == 0 and srgb.g == 0 and srgb.b == 0) continue;

            const offset = noiseAt(x, image_y) * strength;

            srgb.r = Srgb.clampedByte(@as(f32, @floatFromInt(srgb.r)) + offset);
            srgb.g = Srgb.clampedByte(@as(f32, @floatFromInt(srgb.g)) + offset);
            srgb.b = Srgb.clampedByte(@as(f32, @floatFromInt(srgb.b)) + offset);
        }
    }
}

/// Adds grain to a continuous linear band, for use before dithering. The jitter is
/// applied in the gamma-encoded sRGB domain so its strength matches `apply`, but stays
/// in f32 so faint detail survives for the dither instead of being flattened by an
/// 8-bit round-trip. Unlike `apply`, the jitter is scaled by pixel brightness: at full
/// strength in deep shadow the dither would amplify it into coarse clumps, so scaling
/// keeps shadows (the prism glow's fade to black) clean while highlights keep their
/// film texture.
pub fn applyLinear(self: Self, band: Image.Band(Linear)) void {
    std.debug.assert(self.normalized_deviation >= 0.0 and self.normalized_deviation <= 1.0);

    if (self.normalized_deviation == 0.0) return;

    // The same ±swing as apply, on the normalized 0–1 sRGB scale.
    const strength = self.normalized_deviation * 2.0;

    for (0..band.bandHeight()) |local_y| {
        const image_y = band.imageY(local_y);
        const row = band.buffer[local_y * band.width ..][0..band.width];

        for (row, 0..) |*linear, x| {
            // Leave pure black untextured so the dark background stays clean.
            if (linear.vec[0] == 0 and linear.vec[1] == 0 and linear.vec[2] == 0) continue;

            const vec = linear.vec;
            const brightness = Linear.linearToSrgbComponent(@max(vec[0], @max(vec[1], vec[2])));
            const offset = noiseAt(x, image_y) * strength * brightness;

            linear.vec = .{
                grainChannel(vec[0], offset),
                grainChannel(vec[1], offset),
                grainChannel(vec[2], offset),
                vec[3],
            };
        }
    }
}

/// Deterministic per-pixel noise in [-0.5, 0.5] from a Murmur-style position hash.
fn noiseAt(x: usize, image_y: usize) f32 {
    const hash_y: u32 = @as(u32, @bitCast(@as(i32, @intCast(image_y)))) *% 668265263;
    const hash_x: u32 = @intCast(x);

    var h = hash_x *% 374761393 +% hash_y;

    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;

    // Upper 24 bits (>> 8) give smoother noise than 8 bits would.
    const hash_f: f32 = @floatFromInt(h >> 8);

    return hash_f * (1.0 / 16777215.0) - 0.5;
}

/// Applies a normalized sRGB-domain offset to one linear-light channel.
fn grainChannel(linear_value: f32, offset: f32) f32 {
    const encoded = std.math.clamp(Linear.linearToSrgbComponent(linear_value) + offset, 0.0, 1.0);

    return Srgb.srgbToLinearComponent(encoded);
}

test "apply modifies non-black pixels" {
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** pixel_count;

    const band = try (Image.init(64, 64)).band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(band);

    var changed = false;

    for (&buffer) |pixel| {
        if (pixel.r != 180 or pixel.g != 180 or pixel.b != 180) {
            changed = true;
            break;
        }
    }

    try std.testing.expect(changed);
}

test "apply is no-op when deviation is zero" {
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 128, .g = 128, .b = 128 }} ** pixel_count;

    const original = buffer;
    const band = try (Image.init(64, 64)).band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.0 };

    grain.apply(band);

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "apply skips black pixels" {
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 0, .g = 0, .b = 0 }} ** pixel_count;

    const original = buffer;
    const band = try (Image.init(64, 64)).band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(band);

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "applyLinear modifies non-black pixels" {
    const pixel_count = 64 * 64;

    var buffer = [_]Linear{Linear.init(0.5, 0.5, 0.5, 1.0)} ** pixel_count;

    const band = try (Image.init(64, 64)).band(Linear, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.applyLinear(band);

    var changed = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] != 0.5 or pixel.vec[1] != 0.5 or pixel.vec[2] != 0.5) {
            changed = true;
            break;
        }
    }

    try std.testing.expect(changed);
}

test "applyLinear is a no-op when deviation is zero" {
    const pixel_count = 64 * 64;

    var buffer = [_]Linear{Linear.init(0.3, 0.6, 0.1, 1.0)} ** pixel_count;

    const original = buffer;
    const band = try (Image.init(64, 64)).band(Linear, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.0 };

    grain.applyLinear(band);

    for (buffer, original) |actual, expected| {
        try std.testing.expectEqual(expected.vec, actual.vec);
    }
}

test "applyLinear leaves pure black untextured and preserves alpha" {
    const pixel_count = 64 * 64;

    var buffer = [_]Linear{Linear.init(0.0, 0.0, 0.0, 0.5)} ** pixel_count;

    const band = try (Image.init(64, 64)).band(Linear, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.5 };

    grain.applyLinear(band);

    for (buffer) |pixel| {
        try std.testing.expectEqual(@as(f32, 0.0), pixel.vec[0]);
        try std.testing.expectEqual(@as(f32, 0.0), pixel.vec[1]);
        try std.testing.expectEqual(@as(f32, 0.0), pixel.vec[2]);
        try std.testing.expectEqual(@as(f32, 0.5), pixel.vec[3]);
    }
}

test "applyLinear scales jitter by pixel brightness" {
    const width = 64;
    const height = 64;
    const pixel_count = width * height;
    const image = Image.init(width, height);

    const grain = Self{ .normalized_deviation = 0.1 };

    // Two uniform fields share the same per-pixel noise at matching positions, so the
    // brightness factor is the only thing that can differ in their jitter. The dim field
    // must accumulate strictly less total jitter than the bright one: equal totals would
    // mean the scaling was dropped, more-for-dim that it was inverted.
    const dim_value: f32 = 0.01;
    const bright_value: f32 = 0.5;

    var dim_buffer = [_]Linear{Linear.init(dim_value, dim_value, dim_value, 1.0)} ** pixel_count;
    var bright_buffer = [_]Linear{Linear.init(bright_value, bright_value, bright_value, 1.0)} ** pixel_count;

    grain.applyLinear(try image.band(Linear, &dim_buffer, height, 0));
    grain.applyLinear(try image.band(Linear, &bright_buffer, height, 0));

    const dim_encoded = Linear.linearToSrgbComponent(dim_value);
    const bright_encoded = Linear.linearToSrgbComponent(bright_value);

    var dim_jitter: f32 = 0.0;
    var bright_jitter: f32 = 0.0;

    for (dim_buffer, bright_buffer) |dim_pixel, bright_pixel| {
        dim_jitter += @abs(Linear.linearToSrgbComponent(dim_pixel.vec[0]) - dim_encoded);
        bright_jitter += @abs(Linear.linearToSrgbComponent(bright_pixel.vec[0]) - bright_encoded);
    }

    try std.testing.expect(dim_jitter > 0.0);
    try std.testing.expect(bright_jitter > dim_jitter);
}

test "multi-band applyLinear matches single-band applyLinear" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    var input: [pixel_count]Linear = undefined;

    for (0..height) |y| {
        const t: f32 = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));

        for (0..width) |x| {
            const s: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1));

            // Offset away from pure black so every pixel is grained.
            input[y * width + x] = Linear.init(t * 0.8 + 0.1, s * 0.5 + 0.1, 0.3, 1.0);
        }
    }

    const grain = Self{ .normalized_deviation = 0.2 };

    var reference = input;

    const full_band = try image.band(Linear, &reference, height, 0);

    grain.applyLinear(full_band);

    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            const narrow_band = try image.band(
                Linear,
                banded_output[row_start..][0..band_pixels],
                band_height,
                band_index,
            );

            grain.applyLinear(narrow_band);
        }

        for (reference, banded_output) |ref, actual| {
            try std.testing.expectEqual(ref.vec, actual.vec);
        }
    }
}

test "multi-band grain matches single-band grain" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    var input: [pixel_count]Srgb = undefined;

    for (0..height) |y| {
        const t: u8 = @intCast(y * 255 / (height - 1));

        for (0..width) |x| {
            const s: u8 = @intCast(x * 255 / (width - 1));

            input[y * width + x] = .{ .r = t, .g = s, .b = 128 };
        }
    }

    const grain = Self{ .normalized_deviation = 0.1 };

    // Reference: single-band (full height)
    var reference = input;

    const full_band = try image.band(Srgb, &reference, height, 0);

    grain.apply(full_band);

    // Test with band heights: 1 (extreme), 2 (even), 3 (odd), 4 (even), 8, 16
    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            const narrow_band = try image.band(
                Srgb,
                banded_output[row_start..][0..band_pixels],
                band_height,
                band_index,
            );

            grain.apply(narrow_band);
        }

        for (&reference, &banded_output, 0..) |ref, actual, i| {
            const y = i / width;
            const x = i % width;

            std.testing.expectEqual(ref.r, actual.r) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) r: expected {d}, got {d}\n",
                    .{ band_height, x, y, ref.r, actual.r },
                );

                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.g, actual.g) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) g: expected {d}, got {d}\n",
                    .{ band_height, x, y, ref.g, actual.g },
                );

                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.b, actual.b) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) b: expected {d}, got {d}\n",
                    .{ band_height, x, y, ref.b, actual.b },
                );

                return error.TestUnexpectedResult;
            };
        }
    }
}
