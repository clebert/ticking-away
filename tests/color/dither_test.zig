const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const dither = lib.dither;

test "color count" {
    try std.testing.expectEqual(6, dither.color_count);
}

test "find closest color" {
    const cache = dither.getPaletteCache(.ideal);

    // Pure red should match red
    const red = (color_space.Srgba{ .r = 255, .g = 0, .b = 0 }).toOklab();
    const red_color = cache.findClosest(red, 2.0);
    try std.testing.expectEqual(dither.Color.red, red_color);

    // Pure black should match black
    const black = (color_space.Srgba{ .r = 0, .g = 0, .b = 0 }).toOklab();
    const black_color = cache.findClosest(black, 2.0);
    try std.testing.expectEqual(dither.Color.black, black_color);
}
