const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const dither = lib.dither;
const ordered = lib.ordered;

test "ordered dithering rgba output" {
    const palette_cache = dither.getPaletteCache(.ideal);

    var linear_colors = [_]color_space.Linear{
        color_space.Linear.init(0.0, 0.0, 0.0, 1.0), // Black
        color_space.Linear.init(1.0, 1.0, 1.0, 1.0), // White
        color_space.Linear.init(1.0, 0.0, 0.0, 1.0), // Red
        color_space.Linear.init(0.0, 0.0, 1.0, 1.0), // Blue
    };

    var srgba_colors: [16]u8 = undefined;
    const config = ordered.Config{ .matrix = .bayer2x2, .spread = 0.5 };

    ordered.applyRgba(&linear_colors, &srgba_colors, 2, 2, config, palette_cache);

    // Black should output black (0, 0, 0)
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[0]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[1]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[2]);

    // White should output white (255, 255, 255)
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[4]);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[5]);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[6]);

    // Red should output red (255, 0, 0)
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[8]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[9]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[10]);

    // Blue should output blue (0, 0, 255)
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[12]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[13]);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[14]);
}

test "ordered dithering matrix sizes" {
    const palette_cache = dither.getPaletteCache(.ideal);

    var linear_colors = [_]color_space.Linear{color_space.Linear.init(0.5, 0.5, 0.5, 1.0)} ** 64;
    var srgba_colors: [256]u8 = undefined;

    // All matrix sizes should work without error
    inline for ([_]ordered.Matrix{ .bayer2x2, .bayer4x4, .bayer8x8 }) |matrix| {
        const config = ordered.Config{ .matrix = matrix, .spread = 0.5 };
        ordered.applyRgba(&linear_colors, &srgba_colors, 8, 8, config, palette_cache);
    }
}
