const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;

test "srgb round-trip" {
    const test_values = [_]f32{ 0.0, 0.001, 0.01, 0.1, 0.5, 0.9, 1.0 };
    for (test_values) |linear| {
        const linear_color = color_space.Linear.init(linear, linear, linear, 1.0);
        const srgb = linear_color.toSrgb();
        const back = (color_space.Srgb{ .r = srgb.r, .g = srgb.g, .b = srgb.b }).toLinear();
        try std.testing.expectApproxEqAbs(linear, back.vec[0], 0.01);
    }
}

test "gamma known values" {
    const black = color_space.Linear.init(0.0, 0.0, 0.0, 1.0).toSrgb();
    try std.testing.expectEqual(@as(u8, 0), black.r);

    const white = color_space.Linear.init(1.0, 1.0, 1.0, 1.0).toSrgb();
    try std.testing.expectEqual(@as(u8, 255), white.r);

    // Linear 0.214 should map to approximately sRGB 0.5 (127-128)
    const mid = color_space.Linear.init(0.214, 0.214, 0.214, 1.0).toSrgb();
    try std.testing.expect(mid.r >= 125 and mid.r <= 130);
}

test "oklab round-trip" {
    const test_colors = [_]color_space.Linear{
        color_space.Linear.init(0, 0, 0, 1),
        color_space.Linear.init(1, 1, 1, 1),
        color_space.Linear.init(1, 0, 0, 1),
        color_space.Linear.init(0, 1, 0, 1),
        color_space.Linear.init(0, 0, 1, 1),
        color_space.Linear.init(0.5, 0.5, 0.5, 1),
    };

    for (test_colors) |c| {
        const lab = c.toOklab();
        const back = lab.toLinear();
        try std.testing.expectApproxEqAbs(c.vec[0], back.vec[0], 0.001);
        try std.testing.expectApproxEqAbs(c.vec[1], back.vec[1], 0.001);
        try std.testing.expectApproxEqAbs(c.vec[2], back.vec[2], 0.001);
    }
}

test "oklab known values" {
    const black = color_space.Linear.init(0, 0, 0, 1).toOklab();
    try std.testing.expectApproxEqAbs(black.vec[0], 0.0, 0.001);

    const white = color_space.Linear.init(1, 1, 1, 1).toOklab();
    try std.testing.expectApproxEqAbs(white.vec[0], 1.0, 0.001);
    try std.testing.expectApproxEqAbs(white.vec[1], 0.0, 0.01);
    try std.testing.expectApproxEqAbs(white.vec[2], 0.0, 0.01);
}

test "oklab lerp" {
    const black = color_space.Linear.init(0, 0, 0, 1).toOklab();
    const white = color_space.Linear.init(1, 1, 1, 1).toOklab();

    const mid = color_space.Oklab.lerp(black, white, 0.5);
    try std.testing.expectApproxEqAbs(mid.vec[0], 0.5, 0.01);
}
