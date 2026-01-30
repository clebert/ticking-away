const std = @import("std");
const testing = std.testing;
const pi = std.math.pi;
const tau = std.math.tau;

/// Use standard math implementations instead of fast approximations.
pub const use_std_math = true;

/// Reduces angle to [-pi, pi] range.
inline fn reduceAngle(x: f32) f32 {
    @setFloatMode(.optimized);
    const inv_tau = 1.0 / tau;
    const n = x * inv_tau;
    var ni: i32 = @intFromFloat(n);
    if (n < @as(f32, @floatFromInt(ni))) {
        ni -= 1;
    }
    var result = x - @as(f32, @floatFromInt(ni)) * tau;
    if (result > pi) {
        result -= tau;
    }
    if (result < -pi) {
        result += tau;
    }
    return result;
}

/// Sine function.
/// When `use_std_math` is false, uses Bhaskara I's formula.
/// Works entirely in f32, no f64 promotion. Maximum error ~0.001 radians.
/// When `use_std_math` is true, uses standard math implementation.
pub inline fn sin(x: f32) f32 {
    @setFloatMode(.optimized);
    if (use_std_math) {
        return @sin(x);
    }
    const reduced = reduceAngle(x);
    var sign: f32 = 1.0;
    var angle = reduced;
    if (angle < 0.0) {
        angle = -angle;
        sign = -1.0;
    }
    const pmx = pi - angle;
    const num = 16.0 * angle * pmx;
    const den = 5.0 * pi * pi - 4.0 * angle * pmx;
    return sign * num / den;
}

/// Cosine function.
/// When `use_std_math` is false, uses cos(x) = sin(x + pi/2).
/// When `use_std_math` is true, uses standard math implementation.
pub inline fn cos(x: f32) f32 {
    @setFloatMode(.optimized);
    if (use_std_math) {
        return @cos(x);
    }
    return sin(x + pi / 2.0);
}

/// Two-argument arctangent function.
/// Returns angle in radians in range [-pi, pi].
/// When `use_std_math` is false, uses polynomial approximation (max error ~0.2%).
/// When `use_std_math` is true, uses standard math implementation.
pub inline fn atan2(y: f32, x: f32) f32 {
    @setFloatMode(.optimized);
    if (use_std_math) {
        return std.math.atan2(y, x);
    }
    if (x == 0.0) {
        if (y > 0.0) return pi * 0.5;
        if (y < 0.0) return -pi * 0.5;
        return 0.0;
    }
    if (y == 0.0) {
        return if (x < 0.0) pi else 0.0;
    }

    const abs_y = @abs(y);
    var angle: f32 = 0.0;

    if (x >= 0.0) {
        const r = (x - abs_y) / (x + abs_y);
        angle = 0.1963 * r * r * r - 0.9817 * r + pi / 4.0;
    } else {
        const r = (x + abs_y) / (abs_y - x);
        angle = 0.1963 * r * r * r - 0.9817 * r + 3.0 * pi / 4.0;
    }

    return if (y < 0.0) -angle else angle;
}

test "sin known values" {
    // sin(0) = 0
    try testing.expectApproxEqAbs(sin(0), 0, 0.001);

    // sin(pi/2) = 1
    try testing.expectApproxEqAbs(sin(pi / 2.0), 1, 0.001);

    // sin(pi) = 0
    try testing.expectApproxEqAbs(sin(pi), 0, 0.001);

    // sin(-pi/2) = -1
    try testing.expectApproxEqAbs(sin(-pi / 2.0), -1, 0.001);

    // sin(pi/6) = 0.5
    try testing.expectApproxEqAbs(sin(pi / 6.0), 0.5, 0.01);

    // sin(pi/4) ~= 0.7071
    try testing.expectApproxEqAbs(sin(pi / 4.0), 0.7071, 0.01);
}

test "cos known values" {
    // cos(0) = 1
    try testing.expectApproxEqAbs(cos(0), 1, 0.001);

    // cos(pi/2) = 0
    try testing.expectApproxEqAbs(cos(pi / 2.0), 0, 0.001);

    // cos(pi) = -1
    try testing.expectApproxEqAbs(cos(pi), -1, 0.001);

    // cos(pi/3) = 0.5
    try testing.expectApproxEqAbs(cos(pi / 3.0), 0.5, 0.01);

    // cos(pi/4) ~= 0.7071
    try testing.expectApproxEqAbs(cos(pi / 4.0), 0.7071, 0.01);
}

test "large angle reduction" {
    // Test values outside [-pi, pi]
    try testing.expectApproxEqAbs(sin(tau + pi / 2.0), 1, 0.001);
    try testing.expectApproxEqAbs(sin(-tau + pi / 2.0), 1, 0.001);
    try testing.expectApproxEqAbs(cos(4 * tau), 1, 0.001);
    try testing.expectApproxEqAbs(sin(10 * tau + pi / 6.0), 0.5, 0.01);
}

test "atan2 known values" {
    // atan2(0, 1) = 0 (pointing right)
    try testing.expectApproxEqAbs(atan2(0, 1), 0, 0.01);

    // atan2(1, 0) = pi/2 (pointing up)
    try testing.expectApproxEqAbs(atan2(1, 0), pi / 2.0, 0.01);

    // atan2(0, -1) = pi (pointing left)
    try testing.expectApproxEqAbs(atan2(0, -1), pi, 0.01);

    // atan2(-1, 0) = -pi/2 (pointing down)
    try testing.expectApproxEqAbs(atan2(-1, 0), -pi / 2.0, 0.01);

    // atan2(1, 1) = pi/4 (45 degrees)
    try testing.expectApproxEqAbs(atan2(1, 1), pi / 4.0, 0.01);

    // atan2(-1, 1) = -pi/4 (-45 degrees)
    try testing.expectApproxEqAbs(atan2(-1, 1), -pi / 4.0, 0.01);

    // atan2(1, -1) = 3*pi/4 (135 degrees)
    try testing.expectApproxEqAbs(atan2(1, -1), 3.0 * pi / 4.0, 0.01);

    // atan2(-1, -1) = -3*pi/4 (-135 degrees)
    try testing.expectApproxEqAbs(atan2(-1, -1), -3.0 * pi / 4.0, 0.01);
}
