const std = @import("std");

const vec2 = @import("../math/vec2.zig");

pub const Segment = struct {
    start: vec2.Vec2,
    dir: vec2.Vec2,
    inv_len_sq: f32,

    pub fn init(start: vec2.Vec2, end: vec2.Vec2) Segment {
        @setFloatMode(.optimized);
        const dir = end - start;
        const len_sq = vec2.lengthSq(dir);

        return .{
            .start = start,
            .dir = dir,
            .inv_len_sq = if (len_sq > std.math.floatEps(f32)) 1 / len_sq else 0,
        };
    }

    pub const BoundingBox = struct {
        min: vec2.Vec2,
        max: vec2.Vec2,
    };

    pub fn boundingBox(self: Segment, radius: f32) BoundingBox {
        @setFloatMode(.optimized);
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

    pub const DistanceResult = struct {
        distance_sq: f32,
        t: f32,
    };

    pub fn distanceSq(self: Segment, px: f32, py: f32) DistanceResult {
        @setFloatMode(.optimized);
        const to_x = px - self.start[0];
        const to_y = py - self.start[1];
        const dot_val = to_x * self.dir[0] + to_y * self.dir[1];
        const t = @min(@max(dot_val * self.inv_len_sq, 0), 1);

        const proj_x = self.start[0] + t * self.dir[0];
        const proj_y = self.start[1] + t * self.dir[1];
        const dx = px - proj_x;
        const dy = py - proj_y;

        return .{ .distance_sq = dx * dx + dy * dy, .t = t };
    }
};

