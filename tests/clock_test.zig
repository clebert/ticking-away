const std = @import("std");
const testing = std.testing;
const tau = std.math.tau;
const lib = @import("lib");

const clock = lib.clock;
const vec2 = lib.vec2;

fn minuteAngle(minutes: f32) f32 {
    const angle_0: f32 = -std.math.pi / 2.0;
    return angle_0 + (minutes / 60.0) * tau;
}

test "minute angle" {
    const pi = std.math.pi;

    // 0 minutes = 12 o'clock position (top, -pi/2)
    try testing.expectApproxEqAbs(minuteAngle(0), -pi / 2.0, 1e-6);

    // 15 minutes = 3 o'clock position (right, 0)
    try testing.expectApproxEqAbs(minuteAngle(15), 0, 1e-6);

    // 30 minutes = 6 o'clock position (bottom, pi/2)
    try testing.expectApproxEqAbs(minuteAngle(30), pi / 2.0, 1e-6);

    // 45 minutes = 9 o'clock position (left, pi)
    try testing.expectApproxEqAbs(minuteAngle(45), pi, 1e-6);
}

test "hour angle" {
    const pi = std.math.pi;

    // 12:00 - top position
    try testing.expectApproxEqAbs(clock.hourAngle(0, 0), -pi / 2.0, 1e-6);
    try testing.expectApproxEqAbs(clock.hourAngle(12, 0), -pi / 2.0 + tau, 1e-6);

    // 3:00 - right position
    try testing.expectApproxEqAbs(clock.hourAngle(3, 0), 0, 1e-6);

    // 6:00 - bottom position
    try testing.expectApproxEqAbs(clock.hourAngle(6, 0), pi / 2.0, 1e-6);

    // 9:00 - left position
    try testing.expectApproxEqAbs(clock.hourAngle(9, 0), pi, 1e-6);
}

test "entry point on circle" {
    const center = vec2.xy(100, 100);
    const radius: f32 = 50;

    // 0 minutes - top of circle
    const top = clock.entryPoint(center, radius, 0);
    try testing.expectApproxEqAbs(top[0], 100, 1e-4);
    try testing.expectApproxEqAbs(top[1], 50, 1e-4);

    // 15 minutes - right of circle
    const right = clock.entryPoint(center, radius, 15);
    try testing.expectApproxEqAbs(right[0], 150, 1e-4);
    try testing.expectApproxEqAbs(right[1], 100, 1e-4);

    // 30 minutes - bottom of circle
    const bottom = clock.entryPoint(center, radius, 30);
    try testing.expectApproxEqAbs(bottom[0], 100, 1e-4);
    try testing.expectApproxEqAbs(bottom[1], 150, 1e-4);
}

test "band exit angle spread" {
    const base_angle: f32 = 0;
    const spread: f32 = 1.0; // Full spread
    const max_spread_radians: f32 = std.math.pi / 6.0;

    // First color should be offset one way
    const first = clock.colorExitAngle(base_angle, spread, .red);
    // Last color should be offset the other way
    const last = clock.colorExitAngle(base_angle, spread, .violet);

    // They should be on opposite sides of the base angle
    try testing.expect(first > base_angle);
    try testing.expect(last < base_angle);

    // Total spread should be approximately max_spread_radians
    const total_spread = first - last;
    const count_f: f32 = @floatFromInt(clock.color_count);
    try testing.expectApproxEqAbs(total_spread, max_spread_radians * (1.0 - 1.0 / count_f), 0.01);
}
