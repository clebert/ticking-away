const std = @import("std");
const testing = std.testing;

const vec2 = @import("math/vec2.zig");

pub const angle_0: f32 = -std.math.pi / 2.0;
pub const hour_arc: f32 = std.math.pi / 6.0;
pub const tau: f32 = 2.0 * std.math.pi;
pub const max_spread_radians: f32 = std.math.pi / 6.0;
pub const band_count: usize = 7;

pub fn minuteAngle(minutes: f32) f32 {
    @setFloatMode(.optimized);
    return angle_0 + (minutes / 60.0) * tau;
}

pub fn hourAngle(hours: f32, minutes: f32) f32 {
    @setFloatMode(.optimized);
    return angle_0 + (hours / 12.0) * tau + (minutes / 60.0) * hour_arc;
}

pub fn entryPoint(center: vec2.Vec2, radius: f32, minutes: f32) vec2.Vec2 {
    @setFloatMode(.optimized);
    const angle = minuteAngle(minutes);
    const dir = vec2.xy(@cos(angle), @sin(angle));
    const r_vec: vec2.Vec2 = @splat(radius);
    return center + dir * r_vec;
}

pub fn bandExitAngle(base_hour_angle: f32, rainbow_spread: f32, band_index: usize) f32 {
    @setFloatMode(.optimized);
    const t = (@as(f32, @floatFromInt(band_index)) + 0.5) / @as(f32, @floatFromInt(band_count));
    const spread_rad = rainbow_spread * max_spread_radians;
    const offset = (0.5 - t) * spread_rad;
    return base_hour_angle + offset;
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
    try testing.expectApproxEqAbs(hourAngle(0, 0), -pi / 2.0, 1e-6);
    try testing.expectApproxEqAbs(hourAngle(12, 0), -pi / 2.0 + tau, 1e-6);

    // 3:00 - right position
    try testing.expectApproxEqAbs(hourAngle(3, 0), 0, 1e-6);

    // 6:00 - bottom position
    try testing.expectApproxEqAbs(hourAngle(6, 0), pi / 2.0, 1e-6);

    // 9:00 - left position
    try testing.expectApproxEqAbs(hourAngle(9, 0), pi, 1e-6);
}

test "entry point on circle" {
    const center = vec2.xy(100, 100);
    const radius: f32 = 50;

    // 0 minutes - top of circle
    const top = entryPoint(center, radius, 0);
    try testing.expectApproxEqAbs(top[0], 100, 1e-4);
    try testing.expectApproxEqAbs(top[1], 50, 1e-4);

    // 15 minutes - right of circle
    const right = entryPoint(center, radius, 15);
    try testing.expectApproxEqAbs(right[0], 150, 1e-4);
    try testing.expectApproxEqAbs(right[1], 100, 1e-4);

    // 30 minutes - bottom of circle
    const bottom = entryPoint(center, radius, 30);
    try testing.expectApproxEqAbs(bottom[0], 100, 1e-4);
    try testing.expectApproxEqAbs(bottom[1], 150, 1e-4);
}

test "band exit angle spread" {
    const base_angle: f32 = 0;
    const spread: f32 = 1.0; // Full spread

    // First band should be offset one way
    const first = bandExitAngle(base_angle, spread, 0);
    // Last band should be offset the other way
    const last = bandExitAngle(base_angle, spread, band_count - 1);

    // They should be on opposite sides of the base angle
    try testing.expect(first > base_angle);
    try testing.expect(last < base_angle);

    // Total spread should be approximately max_spread_radians
    const total_spread = first - last;
    try testing.expectApproxEqAbs(total_spread, max_spread_radians * (1.0 - 1.0 / @as(f32, @floatFromInt(band_count))), 0.01);
}
