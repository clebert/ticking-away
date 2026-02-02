const std = @import("std");

const vec2 = @import("vec2.zig");

pub const Segment = struct {
    start: vec2.Vec2,
    dir: vec2.Vec2,
    inv_len_sq: f32,

    pub fn init(start: vec2.Vec2, end: vec2.Vec2) Segment {
        const dir = end - start;
        const len_sq = vec2.lengthSq(dir);

        return .{
            .start = start,
            .dir = dir,
            .inv_len_sq = if (len_sq > std.math.floatEps(f32)) 1 / len_sq else 0,
        };
    }

    const BoundingBox = struct {
        min: vec2.Vec2,
        max: vec2.Vec2,
    };

    pub fn boundingBox(self: Segment, radius: f32) BoundingBox {
        const end = self.start + self.dir;

        return .{
            .min = vec2.xy(
                @min(self.start[0], end[0]) - radius,
                @min(self.start[1], end[1]) - radius,
            ),
            .max = vec2.xy(
                @max(self.start[0], end[0]) + radius,
                @max(self.start[1], end[1]) + radius,
            ),
        };
    }

    const Projection = struct {
        distance_sq: f32,
        t: f32,
    };

    pub fn project(self: Segment, point: vec2.Vec2) Projection {
        const to_point = point - self.start;
        const t = std.math.clamp(vec2.dot(to_point, self.dir) * self.inv_len_sq, 0, 1);
        const proj = self.start + @as(vec2.Vec2, @splat(t)) * self.dir;
        const delta = point - proj;

        return .{ .distance_sq = vec2.dot(delta, delta), .t = t };
    }
};
