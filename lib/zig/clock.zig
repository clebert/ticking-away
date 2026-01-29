const std = @import("std");

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
