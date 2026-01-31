const std = @import("std");
const lib = @import("lib");

const dither = lib.dither;
const oklab = lib.oklab;

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
    const red = oklab.srgbToOklab(255, 0, 0);
    const red_idx = cache.findClosest(red, 2.0);
    try std.testing.expectEqual(dither.PaletteIndex.red, red_idx);

    // Pure black should match black
    const black = oklab.srgbToOklab(0, 0, 0);
    const black_idx = cache.findClosest(black, 2.0);
    try std.testing.expectEqual(dither.PaletteIndex.black, black_idx);
}
