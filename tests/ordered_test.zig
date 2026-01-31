const std = @import("std");

const lib = @import("lib");
const color_space = lib.color_space;
const eink = lib.eink;
const frame = lib.frame;
const ordered = lib.ordered;

test "ordered dithering rgba output" {
    const palette_cache = eink.getPaletteCache(.ideal);

    var linear_colors = [_]color_space.Linear{
        color_space.Linear.init(0.0, 0.0, 0.0, 1.0), // Black
        color_space.Linear.init(1.0, 1.0, 1.0, 1.0), // White
        color_space.Linear.init(1.0, 0.0, 0.0, 1.0), // Red
        color_space.Linear.init(0.0, 0.0, 1.0, 1.0), // Blue
    };

    var srgba_colors: [4]color_space.Srgba = undefined;

    var band = frame.Band{
        .linear_colors = &linear_colors,
        .srgba_colors = &srgba_colors,
        .width = 2,
        .height = 2,
        .y_offset = 0,
        .total_height = 2,
    };

    const config = ordered.Config{ .matrix = .bayer2x2, .spread = 0.5 };

    ordered.apply(&band, config, palette_cache);

    // Black should output black (0, 0, 0)
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[0].r);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[0].g);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[0].b);

    // White should output white (255, 255, 255)
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[1].r);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[1].g);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[1].b);

    // Red should output red (255, 0, 0)
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[2].r);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[2].g);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[2].b);

    // Blue should output blue (0, 0, 255)
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[3].r);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[3].g);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[3].b);
}

test "ordered dithering matrix sizes" {
    const palette_cache = eink.getPaletteCache(.ideal);

    var linear_colors = [_]color_space.Linear{color_space.Linear.init(0.5, 0.5, 0.5, 1.0)} ** 64;
    var srgba_colors: [64]color_space.Srgba = undefined;

    var band = frame.Band{
        .linear_colors = &linear_colors,
        .srgba_colors = &srgba_colors,
        .width = 8,
        .height = 8,
        .y_offset = 0,
        .total_height = 8,
    };

    // All matrix sizes should work without error
    inline for ([_]ordered.Matrix{ .bayer2x2, .bayer4x4, .bayer8x8 }) |matrix| {
        const config = ordered.Config{ .matrix = matrix, .spread = 0.5 };
        ordered.apply(&band, config, palette_cache);
    }
}
