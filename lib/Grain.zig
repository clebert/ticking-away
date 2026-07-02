const std = @import("std");

const Image = @import("Image.zig");
const Prism = @import("Prism.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

/// Maximum per-pixel deviation as a fraction of the sRGB range (0.0–1.0).
normalized_deviation: f32,

/// Adds film-like grain: a per-pixel luminance jitter applied to the 8-bit sRGB band.
/// Confined to the prism interior, so the dispersed rainbow outside it stays smooth.
pub fn apply(self: Self, band: Image.Band(Srgb), viewport: anytype, prism: Prism) void {
    std.debug.assert(self.normalized_deviation >= 0.0 and self.normalized_deviation <= 1.0);

    if (self.normalized_deviation == 0.0) return;

    // ×255×2 maps deviation 1.0 to a full ±255 swing.
    const strength = self.normalized_deviation * 255.0 * 2.0;

    for (0..band.bandHeight()) |local_y| {
        const image_y = band.imageY(local_y);
        const pixel_y: f32 = @as(f32, @floatFromInt(image_y)) + 0.5;
        const row = band.buffer[local_y * band.width ..][0..band.width];

        for (row, 0..) |*srgb, x| {
            // Leave the flat background untouched so it stays clean.
            const is_black = srgb.r == 0 and srgb.g == 0 and srgb.b == 0;
            const is_background = srgb.r == Srgb.background.r and
                srgb.g == Srgb.background.g and srgb.b == Srgb.background.b;

            if (is_black or is_background) continue;

            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;

            if (!prism.containsPoint(viewport.toNormalized(.{ pixel_x, pixel_y }))) continue;

            const offset = noiseAt(x, image_y) * strength;

            srgb.r = Srgb.clampedByte(@as(f32, @floatFromInt(srgb.r)) + offset);
            srgb.g = Srgb.clampedByte(@as(f32, @floatFromInt(srgb.g)) + offset);
            srgb.b = Srgb.clampedByte(@as(f32, @floatFromInt(srgb.b)) + offset);
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

    // Upper 24 bits (>> 8) pair with the 2^24-1 divisor below.
    const hash_f: f32 = @floatFromInt(h >> 8);

    return hash_f * (1.0 / 16777215.0) - 0.5;
}

test "apply modifies non-black pixels" {
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** pixel_count;

    const image = Image.init(64, 64);
    const band = try image.band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(band, image.viewport(), Prism.init(0.8));

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
    const image = Image.init(64, 64);
    const band = try image.band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.0 };

    grain.apply(band, image.viewport(), Prism.init(0.8));

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "apply skips black pixels" {
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 0, .g = 0, .b = 0 }} ** pixel_count;

    const original = buffer;
    const image = Image.init(64, 64);
    const band = try image.band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(band, image.viewport(), Prism.init(0.8));

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "apply skips background pixels" {
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{Srgb.background} ** pixel_count;

    const original = buffer;
    const image = Image.init(64, 64);
    const band = try image.band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(band, image.viewport(), Prism.init(0.8));

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "apply is confined to the prism interior" {
    const size = 64;
    const pixel_count = size * size;

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** pixel_count;

    const image = Image.init(size, size);
    const viewport = image.viewport();
    const prism = Prism.init(0.8);

    const band = try image.band(Srgb, &buffer, size, 0);
    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(band, viewport, prism);

    var changed_outside: usize = 0;
    var changed_inside: usize = 0;

    for (buffer, 0..) |pixel, i| {
        const x: f32 = @as(f32, @floatFromInt(i % size)) + 0.5;
        const y: f32 = @as(f32, @floatFromInt(i / size)) + 0.5;
        const inside = prism.containsPoint(viewport.toNormalized(.{ x, y }));

        if (pixel.r == 180 and pixel.g == 180 and pixel.b == 180) continue;

        if (inside) changed_inside += 1 else changed_outside += 1;
    }

    try std.testing.expectEqual(@as(usize, 0), changed_outside);
    try std.testing.expect(changed_inside > 0);
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
    const viewport = image.viewport();
    const prism = Prism.init(0.8);

    var reference = input;

    const full_band = try image.band(Srgb, &reference, height, 0);

    grain.apply(full_band, viewport, prism);

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

            grain.apply(narrow_band, viewport, prism);
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
