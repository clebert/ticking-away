const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const dither = lib.dither;
const ordered = lib.ordered;

test "ordered dithering rgba output" {
    const palette_cache = dither.PaletteCache.init(&dither.palette_ideal);

    var buffer = [_]color_space.Linear{
        color_space.Linear.init(0.0, 0.0, 0.0, 1.0), // Black
        color_space.Linear.init(1.0, 1.0, 1.0, 1.0), // White
        color_space.Linear.init(1.0, 0.0, 0.0, 1.0), // Red
        color_space.Linear.init(0.0, 0.0, 1.0, 1.0), // Blue
    };

    var out_rgba: [16]u8 = undefined;
    const config = ordered.Config{ .matrix = .bayer2x2, .spread = 0.5 };

    ordered.applyRgba(&buffer, &out_rgba, 2, 2, config, &palette_cache);

    // Black should output black (0, 0, 0)
    try std.testing.expectEqual(@as(u8, 0), out_rgba[0]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[1]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[2]);

    // White should output white (255, 255, 255)
    try std.testing.expectEqual(@as(u8, 255), out_rgba[4]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[5]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[6]);

    // Red should output red (255, 0, 0)
    try std.testing.expectEqual(@as(u8, 255), out_rgba[8]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[9]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[10]);

    // Blue should output blue (0, 0, 255)
    try std.testing.expectEqual(@as(u8, 0), out_rgba[12]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[13]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[14]);
}

test "ordered dithering matrix sizes" {
    const palette_cache = dither.PaletteCache.init(&dither.palette_ideal);

    var buffer = [_]color_space.Linear{color_space.Linear.init(0.5, 0.5, 0.5, 1.0)} ** 64;
    var out_rgba: [256]u8 = undefined;

    // All matrix sizes should work without error
    inline for ([_]ordered.Matrix{ .bayer2x2, .bayer4x4, .bayer8x8 }) |matrix| {
        const config = ordered.Config{ .matrix = matrix, .spread = 0.5 };
        ordered.applyRgba(&buffer, &out_rgba, 8, 8, config, &palette_cache);
    }
}
