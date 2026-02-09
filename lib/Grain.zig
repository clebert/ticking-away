const std = @import("std");

const Image = @import("Image.zig");
const Prism = @import("Prism.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

/// Maximum per-pixel deviation as a fraction of the sRGB range (0.0–1.0).
/// At 1.0, each pixel can shift by up to ±127.5 sRGB units.
normalized_deviation: f32,

pub fn apply(self: Self, band: *Image.Band(Srgb), viewport: Image.Viewport, prism: Prism) void {
    std.debug.assert(self.normalized_deviation >= 0.0 and self.normalized_deviation <= 1.0);

    if (self.normalized_deviation == 0.0) return;

    // noise_raw ∈ [-0.5, 0.5], so multiply by 2 to scale to peak-to-peak
    const strength = self.normalized_deviation * 255.0 * 2.0;

    // Prism bounding box in pixel space
    const prism_bounds = prism.bounds();
    const pixel_min = viewport.toPixel(.{ prism_bounds[0], prism_bounds[1] });
    const pixel_max = viewport.toPixel(.{ prism_bounds[2], prism_bounds[3] });

    const x_start: usize = if (pixel_min[0] < 0.5) 0 else @intFromFloat(pixel_min[0] - 0.5);
    const x_end: usize = @min(
        if (pixel_max[0] < 0) 0 else @as(usize, @intFromFloat(pixel_max[0] + 0.5)) + 1,
        band.width,
    );

    for (0..band.bandHeight()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));

        if (y + 0.5 < pixel_min[1] or y + 0.5 > pixel_max[1]) continue;
        if (x_start >= x_end) continue;

        // Murmur-style hash: pixel position → deterministic noise
        const hash_y: u32 = @as(u32, @bitCast(@as(i32, @intFromFloat(y)))) *% 668265263;

        const row = band.buffer[local_y * band.width ..][x_start..x_end];

        for (row, x_start..) |*srgb, x| {
            if (srgb.r == 0 and srgb.g == 0 and srgb.b == 0) continue;

            const pixel_center: @Vector(2, f32) = .{ @as(f32, @floatFromInt(x)) + 0.5, y + 0.5 };

            if (!prism.containsPoint(viewport.toNormalized(pixel_center))) continue;

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

            srgb.r = @intFromFloat(@min(@max(r + grain, 0.0), 255.0));
            srgb.g = @intFromFloat(@min(@max(g + grain, 0.0), 255.0));
            srgb.b = @intFromFloat(@min(@max(b + grain, 0.0), 255.0));
        }
    }
}

const test_prism = Prism.init(0.8);

test "apply modifies pixels inside prism" {
    const image = Image.init(64, 64);
    const viewport = image.viewport();
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** pixel_count;
    var band = image.band(Srgb, &buffer, 64, 0) catch unreachable;

    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(&band, viewport, test_prism);

    var changed = false;

    for (&buffer) |pixel| {
        if (pixel.r != 180 or pixel.g != 180 or pixel.b != 180) {
            changed = true;
            break;
        }
    }

    try std.testing.expect(changed);
}

test "apply skips pixels outside prism" {
    const image = Image.init(64, 64);
    const viewport = image.viewport();
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** pixel_count;
    var band = image.band(Srgb, &buffer, 64, 0) catch unreachable;

    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(&band, viewport, test_prism);

    // Corner pixel (0,0) is far from center — outside prism
    try std.testing.expectEqual(@as(u8, 180), buffer[0].r);
    try std.testing.expectEqual(@as(u8, 180), buffer[0].g);
    try std.testing.expectEqual(@as(u8, 180), buffer[0].b);
}

test "apply is no-op when deviation is zero" {
    const image = Image.init(64, 64);
    const viewport = image.viewport();
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 128, .g = 128, .b = 128 }} ** pixel_count;

    const original = buffer;

    var band = image.band(Srgb, &buffer, 64, 0) catch unreachable;

    const grain = Self{ .normalized_deviation = 0.0 };

    grain.apply(&band, viewport, test_prism);

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "apply skips black pixels" {
    const image = Image.init(64, 64);
    const viewport = image.viewport();
    const pixel_count = 64 * 64;

    var buffer = [_]Srgb{.{ .r = 0, .g = 0, .b = 0 }} ** pixel_count;

    const original = buffer;

    var band = image.band(Srgb, &buffer, 64, 0) catch unreachable;

    const grain = Self{ .normalized_deviation = 0.1 };

    grain.apply(&band, viewport, test_prism);

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "multi-band grain matches single-band grain" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const viewport = image.viewport();
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
    var full_band = image.band(Srgb, &reference, height, 0) catch unreachable;

    grain.apply(&full_band, viewport, test_prism);

    // Test with band heights: 1 (extreme), 2 (even), 3 (odd), 4 (even), 8, 16
    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            var narrow_band = image.band(Srgb, banded_output[row_start..][0..band_pixels], band_height, band_index) catch unreachable;

            grain.apply(&narrow_band, viewport, test_prism);
        }

        for (&reference, &banded_output, 0..) |ref, actual, i| {
            const y = i / width;
            const x = i % width;

            std.testing.expectEqual(ref.r, actual.r) catch {
                std.debug.print("band_height={d}: mismatch at ({d},{d}) r: expected {d}, got {d}\n", .{ band_height, x, y, ref.r, actual.r });

                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.g, actual.g) catch {
                std.debug.print("band_height={d}: mismatch at ({d},{d}) g: expected {d}, got {d}\n", .{ band_height, x, y, ref.g, actual.g });

                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.b, actual.b) catch {
                std.debug.print("band_height={d}: mismatch at ({d},{d}) b: expected {d}, got {d}\n", .{ band_height, x, y, ref.b, actual.b });

                return error.TestUnexpectedResult;
            };
        }
    }
}
