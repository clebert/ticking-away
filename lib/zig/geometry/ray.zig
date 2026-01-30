const std = @import("std");

const trig = @import("../math/trig.zig");
const vec2 = @import("../math/vec2.zig");

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
        @setFloatMode(.optimized);
        return .{
            .origin = origin,
            .direction = vec2.xy(trig.cos(angle), trig.sin(angle)),
        };
    }

    pub fn pointAt(self: Ray, t: f32) vec2.Vec2 {
        @setFloatMode(.optimized);
        const t_vec: vec2.Vec2 = @splat(t);
        return self.origin + self.direction * t_vec;
    }
};
