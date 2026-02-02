const std = @import("std");

const lib = @import("lib");
const rainbow = lib.rainbow;

test "palette cache init" {
    const cache = rainbow.getPaletteCache(.oklch_balanced);

    // First band should be reddish
    try std.testing.expect(cache.linear_colors[0].vec[0] > 0.5); // High red
    try std.testing.expect(cache.linear_colors[0].vec[2] < 0.1); // Low blue

    // Last band should be violet
    try std.testing.expect(cache.linear_colors[6].vec[2] > 0.5); // High blue
}

test "palette interpolation" {
    const cache = rainbow.getPaletteCache(.spectral);

    // t=0 should give red
    const red = cache.interpolate(0.0);
    try std.testing.expect(red.vec[0] > 0.8);
    try std.testing.expect(red.vec[1] < 0.1);
    try std.testing.expect(red.vec[2] < 0.1);

    // t=1 should give violet
    const violet = cache.interpolate(1.0);
    try std.testing.expect(violet.vec[2] > 0.5); // Blue component

    // t=0.5 should be somewhere in the middle (greenish)
    const mid = cache.interpolate(0.5);
    try std.testing.expect(mid.vec[1] > 0.3); // Green component
}

test "palette extrapolation" {
    const cache = rainbow.getPaletteCache(.spectral);

    // t < 0 should give darker red (infrared)
    const ir = cache.interpolate(-0.5);
    try std.testing.expect(ir.vec[0] > 0.0);
    try std.testing.expect(ir.vec[0] < 1.0);

    // t > 1 should give ultraviolet
    const uv = cache.interpolate(1.5);
    try std.testing.expect(uv.vec[2] > 0.0);
}
