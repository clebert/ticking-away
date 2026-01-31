const std = @import("std");
const lib = @import("lib");

const color = lib.color;
const dither = lib.dither;
const ordered = lib.ordered;

test "bayer 2x2 matrix values" {
    try std.testing.expectEqual(@as(f32, -0.5), ordered.getThreshold(.bayer2x2, 0, 0));
    try std.testing.expectEqual(@as(f32, 0.0), ordered.getThreshold(.bayer2x2, 1, 0));
    try std.testing.expectEqual(@as(f32, 0.25), ordered.getThreshold(.bayer2x2, 0, 1));
    try std.testing.expectEqual(@as(f32, -0.25), ordered.getThreshold(.bayer2x2, 1, 1));
}

test "bayer 4x4 matrix values" {
    const expected = [4][4]f32{
        .{ -0.5, 0.0, -0.375, 0.125 },
        .{ 0.25, -0.25, 0.375, -0.125 },
        .{ -0.3125, 0.1875, -0.4375, 0.0625 },
        .{ 0.4375, -0.0625, 0.3125, -0.1875 },
    };
    for (0..4) |y| {
        for (0..4) |x| {
            try std.testing.expectEqual(expected[y][x], ordered.getThreshold(.bayer4x4, x, y));
        }
    }
}

test "bayer 8x8 matrix values" {
    const expected = [8][8]f32{
        .{ -0.5, 0.0, -0.375, 0.125, -0.46875, 0.03125, -0.34375, 0.15625 },
        .{ 0.25, -0.25, 0.375, -0.125, 0.28125, -0.21875, 0.40625, -0.09375 },
        .{ -0.3125, 0.1875, -0.4375, 0.0625, -0.28125, 0.21875, -0.40625, 0.09375 },
        .{ 0.4375, -0.0625, 0.3125, -0.1875, 0.46875, -0.03125, 0.34375, -0.15625 },
        .{ -0.453125, 0.046875, -0.328125, 0.171875, -0.484375, 0.015625, -0.359375, 0.140625 },
        .{ 0.296875, -0.203125, 0.421875, -0.078125, 0.265625, -0.234375, 0.390625, -0.109375 },
        .{ -0.265625, 0.234375, -0.390625, 0.109375, -0.296875, 0.203125, -0.421875, 0.078125 },
        .{ 0.484375, -0.015625, 0.359375, -0.140625, 0.453125, -0.046875, 0.328125, -0.171875 },
    };
    for (0..8) |y| {
        for (0..8) |x| {
            try std.testing.expectEqual(expected[y][x], ordered.getThreshold(.bayer8x8, x, y));
        }
    }
}

test "bayer threshold range" {
    // All thresholds should be in [-0.5, 0.5]
    for (0..8) |y| {
        for (0..8) |x| {
            const t2 = ordered.getThreshold(.bayer2x2, x, y);
            const t4 = ordered.getThreshold(.bayer4x4, x, y);
            const t8 = ordered.getThreshold(.bayer8x8, x, y);

            try std.testing.expect(t2 >= -0.5 and t2 <= 0.5);
            try std.testing.expect(t4 >= -0.5 and t4 <= 0.5);
            try std.testing.expect(t8 >= -0.5 and t8 <= 0.5);
        }
    }
}

test "ordered dithering indices" {
    const palette = dither.PaletteCache.init(&dither.palette_ideal);

    // Create a simple gradient
    var buffer = [_]color.Color{
        color.rgb(0.0, 0.0, 0.0), // Black
        color.rgb(1.0, 1.0, 1.0), // White
        color.rgb(1.0, 0.0, 0.0), // Red
        color.rgb(0.0, 0.0, 1.0), // Blue
    };

    var indices: [4]u8 = undefined;
    const config = ordered.Config{ .matrix = .bayer2x2, .spread = 0.5 };

    ordered.apply(&buffer, &indices, 2, 2, config, &palette);

    // Black should map to black (index 0)
    try std.testing.expectEqual(@as(u8, 0), indices[0]);
    // White should map to white (index 1)
    try std.testing.expectEqual(@as(u8, 1), indices[1]);
}
