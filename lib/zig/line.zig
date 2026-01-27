const std = @import("std");

const vec2 = @import("vec2.zig");

pub const Segment = struct {
    start: vec2.Vec2,
    end: vec2.Vec2,
};

pub const DistanceResult = struct {
    distance_sq: f32,
    /// Parameter along segment: 0 = start, 1 = end
    t: f32,
};

pub fn segmentDistanceSq(segment: Segment, point: vec2.Vec2) DistanceResult {
    const direction = segment.end - segment.start;
    const length_sq = vec2.lengthSq(direction);

    // Degenerate segment (single point)
    if (length_sq < 1e-9) {
        return .{
            .distance_sq = vec2.lengthSq(point - segment.start),
            .t = 0,
        };
    }

    // Project point onto line, clamp to segment bounds
    const to_point = point - segment.start;
    const t = std.math.clamp(vec2.dot(to_point, direction) / length_sq, 0, 1);
    const projection = segment.start + @as(vec2.Vec2, @splat(t)) * direction;

    return .{
        .distance_sq = vec2.lengthSq(point - projection),
        .t = t,
    };
}

pub fn segmentDistance(segment: Segment, point: vec2.Vec2) f32 {
    return @sqrt(segmentDistanceSq(segment, point).distance_sq);
}
