const std = @import("std");
const lib = @import("lib");

const gamma = lib.gamma;

test "srgb round-trip" {
    const test_values = [_]f32{ 0.0, 0.001, 0.01, 0.1, 0.5, 0.9, 1.0 };
    for (test_values) |linear| {
        const srgb = gamma.linearToSrgb(linear);
        const back = gamma.srgbToLinear(@intFromFloat(@min(@max(srgb * 255.0, 0), 255)));
        try std.testing.expectApproxEqAbs(linear, back, 0.01);
    }
}

test "gamma known values" {
    try std.testing.expectApproxEqAbs(gamma.linearToSrgb(0.0), 0.0, 0.001);
    try std.testing.expectApproxEqAbs(gamma.linearToSrgb(1.0), 1.0, 0.001);

    const linear_mid = 0.214;
    const srgb_mid = gamma.linearToSrgb(linear_mid);
    try std.testing.expectApproxEqAbs(srgb_mid, 0.5, 0.02);
}
