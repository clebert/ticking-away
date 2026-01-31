const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const eink = lib.eink;

test "color count" {
    try std.testing.expectEqual(6, eink.color_count);
}

test "find closest color" {
    const cache = eink.getPaletteCache(.ideal);

    // Pure red should match red
    const red = (color_space.Srgba{ .r = 255, .g = 0, .b = 0 }).toOklab();
    const red_color = cache.findClosest(red, 2.0);
    try std.testing.expectEqual(eink.Color.red, red_color);

    // Pure black should match black
    const black = (color_space.Srgba{ .r = 0, .g = 0, .b = 0 }).toOklab();
    const black_color = cache.findClosest(black, 2.0);
    try std.testing.expectEqual(eink.Color.black, black_color);
}
