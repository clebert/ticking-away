const std = @import("std");
const lib = @import("lib");

const palette = lib.palette;

test "palette cache init" {
    const cache = palette.Cache.init(.oklch_balanced);

    // First band should be reddish
    try std.testing.expect(cache.linear[0][0] > 0.5); // High red
    try std.testing.expect(cache.linear[0][2] < 0.1); // Low blue

    // Last band should be violet
    try std.testing.expect(cache.linear[6][2] > 0.5); // High blue
}

test "palette interpolation" {
    const cache = palette.Cache.init(.saturated);

    // t=0 should give red
    const red = cache.interpolate(0.0);
    try std.testing.expect(red[0] > 0.8);
    try std.testing.expect(red[1] < 0.1);
    try std.testing.expect(red[2] < 0.1);

    // t=1 should give violet
    const violet = cache.interpolate(1.0);
    try std.testing.expect(violet[2] > 0.5); // Blue component

    // t=0.5 should be somewhere in the middle (greenish)
    const mid = cache.interpolate(0.5);
    try std.testing.expect(mid[1] > 0.3); // Green component
}

test "palette extrapolation" {
    const cache = palette.Cache.init(.saturated);

    // t < 0 should give darker red (infrared)
    const ir = cache.interpolate(-0.5);
    try std.testing.expect(ir[0] > 0.0);
    try std.testing.expect(ir[0] < 1.0);

    // t > 1 should give ultraviolet
    const uv = cache.interpolate(1.5);
    try std.testing.expect(uv[2] > 0.0);
}
