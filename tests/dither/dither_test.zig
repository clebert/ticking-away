const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const dither = lib.dither;

test "palette count" {
    try std.testing.expectEqual(6, dither.PaletteCache.palette_size);
    try std.testing.expectEqual(6, dither.palette_ideal.values.len);
    try std.testing.expectEqual(6, dither.palette_spectra6_inky.values.len);
    try std.testing.expectEqual(6, dither.palette_spectra6_epdopt.values.len);
    try std.testing.expectEqual(6, dither.palette_spectra6_trmnl.values.len);
}

test "find closest color" {
    const cache = dither.PaletteCache.init(&dither.palette_ideal);

    // Pure red should match red
    const red = (color_space.Srgb{ .r = 255, .g = 0, .b = 0 }).toOklab();
    const red_idx = cache.findClosest(red, 2.0);
    try std.testing.expectEqual(dither.PaletteIndex.red, red_idx);

    // Pure black should match black
    const black = (color_space.Srgb{ .r = 0, .g = 0, .b = 0 }).toOklab();
    const black_idx = cache.findClosest(black, 2.0);
    try std.testing.expectEqual(dither.PaletteIndex.black, black_idx);
}
