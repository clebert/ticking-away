const std = @import("std");
const tau = std.math.tau;

const rainbow = @import("color/rainbow.zig");
const vec2 = @import("geometry/vec2.zig");

const angle_0: f32 = -std.math.pi / 2.0;
const hour_arc: f32 = std.math.pi / 6.0;
const max_spread_radians: f32 = std.math.pi / 6.0;

pub const color_count = rainbow.color_count;

fn minuteAngle(minutes: f32) f32 {
    return angle_0 + (minutes / 60.0) * tau;
}

pub fn hourAngle(hours: f32, minutes: f32) f32 {
    return angle_0 + (hours / 12.0) * tau + (minutes / 60.0) * hour_arc;
}

pub fn entryPoint(center: vec2.Vec2, radius: f32, minutes: f32) vec2.Vec2 {
    const angle = minuteAngle(minutes);
    const dir = vec2.xy(@cos(angle), @sin(angle));
    const r_vec: vec2.Vec2 = @splat(radius);
    return center + dir * r_vec;
}

pub fn colorExitAngle(base_hour_angle: f32, rainbow_spread: f32, color: rainbow.Color) f32 {
    const index_f: f32 = @floatFromInt(@intFromEnum(color));
    const count_f: f32 = @floatFromInt(rainbow.color_count);
    const t = (index_f + 0.5) / count_f;
    const spread_rad = rainbow_spread * max_spread_radians;
    const offset = (0.5 - t) * spread_rad;
    return base_hour_angle + offset;
}
