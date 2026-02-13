const std = @import("std");

const Dither = @import("Dither.zig");
const Image = @import("Image.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

/// Maximum per-pixel deviation as a fraction of the sRGB range (0.0–1.0).
/// At 1.0, each pixel can shift by up to ±127.5 sRGB units.
normalized_deviation: f32,
dither_palette: ?Dither.Palette = null,

pub fn apply(self: Self, band: Image.Band(Srgb)) void {
    std.debug.assert(self.normalized_deviation >= 0.0 and self.normalized_deviation <= 1.0);

    if (self.normalized_deviation == 0.0) return;

    // noise_raw ∈ [-0.5, 0.5], so multiply by 2 to scale to peak-to-peak
    const strength = self.normalized_deviation * 255.0 * 2.0;

    const black = if (self.dither_palette) |dither_palette| dither_palette.black() else Srgb.black;

    for (0..band.bandHeight()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));

        // Murmur-style hash: pixel position → deterministic noise
        const hash_y: u32 = @as(u32, @bitCast(@as(i32, @intFromFloat(y)))) *% 668265263;

        const row = band.buffer[local_y * band.width ..][0..band.width];

        for (row, 0..) |*srgb, x| {
            if (srgb.r == black.r and srgb.g == black.g and srgb.b == black.b) continue;

            const r: f32 = @floatFromInt(srgb.r);
            const g: f32 = @floatFromInt(srgb.g);
            const b: f32 = @floatFromInt(srgb.b);

            const hash_x: u32 = @intCast(x);

            var h = hash_x *% 374761393 +% hash_y;

            h = (h ^ (h >> 13)) *% 1274126177;
            h ^= h >> 16;

            // Use upper 24 bits (>> 8) for smoother noise than 8-bit would give
            const hash_f: f32 = @floatFromInt(h >> 8);
            const grain = (hash_f * (1.0 / 16777215.0) - 0.5) * strength;

            if (self.dither_palette) |dither_palette| {
                srgb.* = findNearest(dither_palette.srgb_colors, r + grain, g + grain, b + grain);
            } else {
                srgb.r = @intFromFloat(@min(@max(r + grain, 0.0), 255.0));
                srgb.g = @intFromFloat(@min(@max(g + grain, 0.0), 255.0));
                srgb.b = @intFromFloat(@min(@max(b + grain, 0.0), 255.0));
            }
        }
    }
}

// sRGB euclidean distance (not perceptual Oklab) — sufficient for small grain deltas
fn findNearest(colors: [Dither.Palette.color_count]Srgb, r: f32, g: f32, b: f32) Srgb {
    var best_index: usize = 0;
    var best_distance: f32 = std.math.floatMax(f32);

    for (colors, 0..) |color, index| {
        const delta_r = r - @as(f32, @floatFromInt(color.r));
        const delta_g = g - @as(f32, @floatFromInt(color.g));
        const delta_b = b - @as(f32, @floatFromInt(color.b));
        const distance = delta_r * delta_r + delta_g * delta_g + delta_b * delta_b;

        if (distance < best_distance) {
            best_distance = distance;
            best_index = index;
        }
    }

    return colors[best_index];
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

test "apply with palette produces only palette colors" {
    const pixel_count = 64 * 64;
    const dither_palette = Dither.PaletteId.ideal.palette();

    // Fill with white (a dither palette color)
    var buffer = [_]Srgb{.{ .r = 255, .g = 255, .b = 255 }} ** pixel_count;

    const band = try (Image.init(64, 64)).band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.3, .dither_palette = dither_palette };

    grain.apply(band);

    for (buffer) |pixel| {
        var found = false;

        for (dither_palette.srgb_colors) |color| {
            if (pixel.r == color.r and pixel.g == color.g and pixel.b == color.b) {
                found = true;
                break;
            }
        }

        try std.testing.expect(found);
    }
}

test "apply with palette skips palette black" {
    const pixel_count = 64 * 64;
    const dither_palette = Dither.PaletteId.spectra6_epdopt.palette();
    const black = dither_palette.black();

    // Fill with palette black (25, 30, 33) — not pure (0,0,0)
    var buffer = [_]Srgb{.{ .r = black.r, .g = black.g, .b = black.b }} ** pixel_count;

    const original = buffer;
    const band = try (Image.init(64, 64)).band(Srgb, &buffer, 64, 0);
    const grain = Self{ .normalized_deviation = 0.1, .dither_palette = dither_palette };

    grain.apply(band);

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
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
