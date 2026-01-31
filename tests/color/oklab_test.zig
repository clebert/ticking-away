const std = @import("std");
const lib = @import("lib");

const color = lib.color;
const oklab = lib.oklab;

test "oklab round-trip" {
    const test_colors = [_]color.Color{
        color.rgb(0, 0, 0),
        color.rgb(1, 1, 1),
        color.rgb(1, 0, 0),
        color.rgb(0, 1, 0),
        color.rgb(0, 0, 1),
        color.rgb(0.5, 0.5, 0.5),
    };

    for (test_colors) |c| {
        const lab = oklab.OkLab.fromLinearRgb(c);
        const back = lab.toLinearRgb();
        try std.testing.expectApproxEqAbs(c[0], back[0], 0.001);
        try std.testing.expectApproxEqAbs(c[1], back[1], 0.001);
        try std.testing.expectApproxEqAbs(c[2], back[2], 0.001);
    }
}

test "oklab known values" {
    const black = oklab.OkLab.fromLinearRgb(color.rgb(0, 0, 0));
    try std.testing.expectApproxEqAbs(black.l, 0.0, 0.001);

    const white = oklab.OkLab.fromLinearRgb(color.rgb(1, 1, 1));
    try std.testing.expectApproxEqAbs(white.l, 1.0, 0.001);
    try std.testing.expectApproxEqAbs(white.a, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(white.b, 0.0, 0.01);
}

test "oklab lerp" {
    const black = oklab.OkLab.fromLinearRgb(color.rgb(0, 0, 0));
    const white = oklab.OkLab.fromLinearRgb(color.rgb(1, 1, 1));

    const mid = oklab.OkLab.lerp(black, white, 0.5);
    try std.testing.expectApproxEqAbs(mid.l, 0.5, 0.01);
}
