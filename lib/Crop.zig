const std = @import("std");

const Image = @import("Image.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

outside_color: Srgb,

pub fn apply(self: Self, band: Image.Band(Srgb), viewport: anytype) void {
    const radius = viewport.scale - 1.0;
    const radius_squared = radius * radius;
    const center_x = viewport.center[0];
    const center_y = viewport.center[1];

    for (0..band.bandHeight()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));
        const dy = y + 0.5 - center_y;
        const dx_max_squared = radius_squared - dy * dy;

        const row = band.buffer[local_y * band.width ..][0..band.width];

        if (dx_max_squared < 0.0) {
            @memset(row, self.outside_color);

            continue;
        }

        const dx_max = @sqrt(dx_max_squared);
        const x_lo = center_x - 0.5 - dx_max;
        const x_hi = center_x - 0.5 + dx_max;

        // Use @ceil (not @intFromFloat truncation) so left/right margins are symmetric.
        const x_start: usize = if (x_lo < 0) 0 else @intFromFloat(@ceil(x_lo));

        const x_end: usize = @min(
            if (x_hi < 0) 0 else @as(usize, @intFromFloat(x_hi)) + 1,
            band.width,
        );

        if (x_start > 0) {
            @memset(row[0..x_start], self.outside_color);
        }

        if (x_end < band.width) {
            @memset(row[x_end..band.width], self.outside_color);
        }
    }
}

test "apply sets pixels outside circle to outside color" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 100;

    const band = image.band(Srgb, &buffer, 10, 0) catch unreachable;
    const crop = Self{ .outside_color = Srgb.white };

    crop.apply(band, viewport);

    // Corner pixel (0,0) is outside the unit circle — should be white
    try std.testing.expectEqual(Srgb.white, buffer[0]);

    // Center pixel (5,5) is inside the unit circle — should stay black
    try std.testing.expectEqual(Srgb.black, buffer[5 * 10 + 5]);
}

test "apply sets transparent outside color" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 100;

    const band = image.band(Srgb, &buffer, 10, 0) catch unreachable;
    const crop = Self{ .outside_color = Srgb.transparent };

    crop.apply(band, viewport);

    // Corner pixel should be transparent
    try std.testing.expectEqual(@as(u8, 0), buffer[0].a);

    // Center pixel should remain opaque (default alpha=255)
    try std.testing.expectEqual(@as(u8, 255), buffer[5 * 10 + 5].a);
}

test "apply handles wide image" {
    const image = Image.init(20, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 200;

    const band = image.band(Srgb, &buffer, 10, 0) catch unreachable;
    const crop = Self{ .outside_color = Srgb.white };

    crop.apply(band, viewport);

    // Far left pixel (0,5) is outside circle in a wide image (circle radius = 5)
    try std.testing.expectEqual(Srgb.white, buffer[5 * 20 + 0]);

    // Far right pixel (19,5) is also outside
    try std.testing.expectEqual(Srgb.white, buffer[5 * 20 + 19]);

    // Center pixel (10,5) is inside
    try std.testing.expectEqual(Srgb.black, buffer[5 * 20 + 10]);
}

test "multi-band crop matches single-band crop" {
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

    const crop = Self{ .outside_color = .{ .r = 20, .g = 30, .b = 40 } };

    // Reference: single-band (full height)
    var reference = input;

    const full_band = image.band(Srgb, &reference, height, 0) catch unreachable;

    crop.apply(full_band, viewport);

    // Test with band heights: 1 (extreme), 2 (even), 3 (odd), 4 (even), 8, 16
    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            const narrow_band = image.band(
                Srgb,
                banded_output[row_start..][0..band_pixels],
                band_height,
                band_index,
            ) catch unreachable;

            crop.apply(narrow_band, viewport);
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
