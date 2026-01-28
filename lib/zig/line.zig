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

    pub const BoundingBox = struct {
        min: vec2.Vec2,
        max: vec2.Vec2,
    };

    pub fn boundingBox(self: Segment, radius: f32) BoundingBox {
        const end = self.start + self.dir;
        const r: vec2.Vec2 = @splat(radius);

        return .{
            .min = @min(self.start, end) - r,
            .max = @max(self.start, end) + r,
        };
    }

    pub const DistanceResult = struct {
        distance_sq: f32,
        t: f32,
    };

    pub fn distanceSq(self: Segment, point: vec2.Vec2) DistanceResult {
        const to_point = point - self.start;
        const t = std.math.clamp(vec2.dot(to_point, self.dir) * self.inv_len_sq, 0, 1);
        const proj = self.start + @as(vec2.Vec2, @splat(t)) * self.dir;

        return .{
            .distance_sq = vec2.lengthSq(point - proj),
            .t = t,
        };
    }

    /// SIMD: 4 horizontal pixels at once
    pub fn distanceSq4(self: Segment, px: @Vector(4, f32), py: @Vector(4, f32)) struct {
        distance_sq: @Vector(4, f32),
        t: @Vector(4, f32),
    } {
        const start_x: @Vector(4, f32) = @splat(self.start[0]);
        const start_y: @Vector(4, f32) = @splat(self.start[1]);
        const dir_x: @Vector(4, f32) = @splat(self.dir[0]);
        const dir_y: @Vector(4, f32) = @splat(self.dir[1]);
        const inv_len_sq: @Vector(4, f32) = @splat(self.inv_len_sq);
        const zero: @Vector(4, f32) = @splat(0);
        const one: @Vector(4, f32) = @splat(1);

        const to_x = px - start_x;
        const to_y = py - start_y;
        const dot = to_x * dir_x + to_y * dir_y;
        const t = @min(@max(dot * inv_len_sq, zero), one);

        const proj_x = start_x + t * dir_x;
        const proj_y = start_y + t * dir_y;
        const dx = px - proj_x;
        const dy = py - proj_y;

        return .{
            .distance_sq = dx * dx + dy * dy,
            .t = t,
        };
    }
};
