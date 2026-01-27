const std = @import("std");

const vec2 = @import("vec2.zig");

pub const Segment = struct {
    start: vec2.Vec2,
    end: vec2.Vec2,

    pub const DistanceResult = struct {
        distance_sq: f32,
        /// Parameter along segment: 0 = start, 1 = end
        t: f32,
    };

    pub fn distanceSq(self: Segment, point: vec2.Vec2) DistanceResult {
        const direction = self.end - self.start;
        const length_sq = vec2.lengthSq(direction);

        const epsilon = std.math.floatEps(f32);
        const length_sq_epsilon = epsilon * epsilon;

        // Degenerate segment (single point)
        if (length_sq < length_sq_epsilon) {
            return .{
                .distance_sq = vec2.lengthSq(point - self.start),
                .t = 0,
            };
        }

        // Project point onto line, clamp to segment bounds
        const to_point = point - self.start;
        const t = std.math.clamp(vec2.dot(to_point, direction) / length_sq, 0, 1);
        const projection = self.start + @as(vec2.Vec2, @splat(t)) * direction;

        return .{
            .distance_sq = vec2.lengthSq(point - projection),
            .t = t,
        };
    }
};
