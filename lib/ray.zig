const std = @import("std");

const vec2 = @import("vec2.zig");

pub const Ray = struct {
    origin: vec2.Vec2,
    direction: vec2.Vec2,

    pub fn init(origin: vec2.Vec2, direction: vec2.Vec2) Ray {
        return .{
            .origin = origin,
            .direction = vec2.normalize(direction),
        };
    }

    pub fn fromAngle(origin: vec2.Vec2, angle: f32) Ray {
        return .{
            .origin = origin,
            .direction = vec2.xy(@cos(angle), @sin(angle)),
        };
    }

    pub fn pointAt(self: Ray, t: f32) vec2.Vec2 {
        const t_vec: vec2.Vec2 = @splat(t);
        return self.origin + self.direction * t_vec;
    }
};
