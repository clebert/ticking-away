const std = @import("std");

const Image = @import("Image.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

normalized_intensity: f32,
normalized_size: f32,

pub fn apply(self: Self, band: *Image.Band(Srgb), viewport: Image.Viewport) void {
    std.debug.assert(self.normalized_intensity >= 0.0 and self.normalized_intensity <= 1.0);
    std.debug.assert(self.normalized_size > 0.0);

    if (self.normalized_intensity == 0.0) return;

    // max_deviation: peak noise in sRGB units at full intensity
    // noise_raw ∈ [-0.5, 0.5], so multiply by 2 to scale max_deviation to peak
    const max_deviation = 0.06 * 255.0;
    const strength = self.normalized_intensity * max_deviation * 2.0;
    const pixel_size = self.normalized_size * viewport.scale;
    const inverse_size = 1.0 / pixel_size;
    const radius_squared = viewport.scale * viewport.scale;
    const center_x = viewport.center[0];
    const center_y = viewport.center[1];

    for (0..band.bandHeight()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));
        const dy = y + 0.5 - center_y;
        const dx_max_squared = radius_squared - dy * dy;

        if (dx_max_squared < 0.0) continue;

        const dx_max = @sqrt(dx_max_squared);
        const x_lo = center_x - 0.5 - dx_max;
        const x_hi = center_x - 0.5 + dx_max;
        const x_start: usize = if (x_lo < 0) 0 else @intFromFloat(x_lo);

        const x_end: usize = @min(
            if (x_hi < 0) 0 else @as(usize, @intFromFloat(x_hi)) + 1,
            band.width,
        );

        if (x_start >= x_end) continue;

        const grid_y: i32 = @intFromFloat(y * inverse_size);

        // Murmur-style hash: grid position → deterministic noise
        const hash_y: u32 = @as(u32, @bitCast(grid_y)) *% 668265263;

        const row = band.buffer[local_y * band.width ..][x_start..x_end];

        for (row, x_start..) |*srgb, x| {
            if (srgb.r == 0 and srgb.g == 0 and srgb.b == 0) continue;

            const r: f32 = @floatFromInt(srgb.r);
            const g: f32 = @floatFromInt(srgb.g);
            const b: f32 = @floatFromInt(srgb.b);

            const grid_x: u32 = @bitCast(@as(i32, @intFromFloat(@as(f32, @floatFromInt(x)) * inverse_size)));

            var h = grid_x *% 374761393 +% hash_y;

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

test "apply modifies bright pixels" {
    const image = Image.init(4, 4);
    const viewport = image.viewport();

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** 16;
    var band = image.band(Srgb, &buffer, 4, 0) catch unreachable;

    const grain = Self{ .normalized_intensity = 1.0, .normalized_size = 0.5 };

    grain.apply(&band, viewport);

    var changed = false;

    for (&buffer) |pixel| {
        if (pixel.r != 180 or pixel.g != 180 or pixel.b != 180) {
            changed = true;
            break;
        }
    }

    try std.testing.expect(changed);
}

test "apply skips pixels outside radius" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{.{ .r = 180, .g = 180, .b = 180 }} ** 100;
    var band = image.band(Srgb, &buffer, 10, 0) catch unreachable;

    const grain = Self{ .normalized_intensity = 1.0, .normalized_size = 0.5 };

    grain.apply(&band, viewport);

    // Corner pixel (0,0) is far from center (5,5) in a 10x10 image — outside unit circle
    try std.testing.expectEqual(@as(u8, 180), buffer[0].r);
    try std.testing.expectEqual(@as(u8, 180), buffer[0].g);
    try std.testing.expectEqual(@as(u8, 180), buffer[0].b);
}

test "apply is no-op when intensity is zero" {
    const image = Image.init(4, 4);
    const viewport = image.viewport();

    var buffer = [_]Srgb{.{ .r = 128, .g = 128, .b = 128 }} ** 16;

    const original = buffer;

    var band = image.band(Srgb, &buffer, 4, 0) catch unreachable;

    const grain = Self{ .normalized_intensity = 0.0, .normalized_size = 0.5 };

    grain.apply(&band, viewport);

    try std.testing.expectEqualSlices(Srgb, &original, &buffer);
}

test "apply skips black pixels" {
    const image = Image.init(4, 4);
    const viewport = image.viewport();

    var buffer = [_]Srgb{.{ .r = 0, .g = 0, .b = 0 }} ** 16;

    const original = buffer;

    var band = image.band(Srgb, &buffer, 4, 0) catch unreachable;

    const grain = Self{ .normalized_intensity = 1.0, .normalized_size = 0.5 };

    grain.apply(&band, viewport);

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

    const grain = Self{ .normalized_intensity = 1.0, .normalized_size = 0.5 };

    // Reference: single-band (full height)
    var reference = input;
    var full_band = image.band(Srgb, &reference, height, 0) catch unreachable;

    grain.apply(&full_band, viewport);

    // Test with band heights: 1 (extreme), 2 (even), 3 (odd), 4 (even), 8, 16
    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            var narrow_band = image.band(Srgb, banded_output[row_start..][0..band_pixels], band_height, band_index) catch unreachable;

            grain.apply(&narrow_band, viewport);
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
