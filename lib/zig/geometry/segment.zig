const std = @import("std");
const testing = std.testing;

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

test "point on segment has distance zero" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 0);
    const seg = Segment.init(start, end);

    // Point at start
    const r1 = seg.distanceSq(0, 0);
    try testing.expectApproxEqAbs(r1.distance_sq, 0, 1e-6);
    try testing.expectApproxEqAbs(r1.t, 0, 1e-6);

    // Point at end
    const r2 = seg.distanceSq(10, 0);
    try testing.expectApproxEqAbs(r2.distance_sq, 0, 1e-6);
    try testing.expectApproxEqAbs(r2.t, 1, 1e-6);

    // Point in middle
    const r3 = seg.distanceSq(5, 0);
    try testing.expectApproxEqAbs(r3.distance_sq, 0, 1e-6);
    try testing.expectApproxEqAbs(r3.t, 0.5, 1e-6);
}

test "perpendicular distance is correct" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 0);
    const seg = Segment.init(start, end);

    // Point 5 units above middle of segment
    const result = seg.distanceSq(5, 5);

    try testing.expectApproxEqAbs(result.distance_sq, 25, 1e-6); // 5^2 = 25
    try testing.expectApproxEqAbs(result.t, 0.5, 1e-6);
}

test "distance to endpoint when outside segment" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 0);
    const seg = Segment.init(start, end);

    // Point before segment start
    const r1 = seg.distanceSq(-3, 4);
    try testing.expectApproxEqAbs(r1.distance_sq, 25, 1e-6); // 3^2 + 4^2 = 25
    try testing.expectApproxEqAbs(r1.t, 0, 1e-6);

    // Point after segment end
    const r2 = seg.distanceSq(13, 4);
    try testing.expectApproxEqAbs(r2.distance_sq, 25, 1e-6); // 3^2 + 4^2 = 25
    try testing.expectApproxEqAbs(r2.t, 1, 1e-6);
}

test "bounding box with radius" {
    const start = vec2.xy(5, 10);
    const end = vec2.xy(15, 20);
    const seg = Segment.init(start, end);

    const box = seg.boundingBox(2);
    try testing.expectApproxEqAbs(box.min[0], 3, 1e-6); // 5 - 2
    try testing.expectApproxEqAbs(box.min[1], 8, 1e-6); // 10 - 2
    try testing.expectApproxEqAbs(box.max[0], 17, 1e-6); // 15 + 2
    try testing.expectApproxEqAbs(box.max[1], 22, 1e-6); // 20 + 2
}

test "diagonal segment distance" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 10);
    const seg = Segment.init(start, end);

    // Point perpendicular to midpoint
    // Midpoint is (5, 5), perpendicular direction is (-1, 1) normalized
    const dist = 3.0;
    const offset = dist / @sqrt(2.0);
    const px = 5 - offset;
    const py = 5 + offset;
    const result = seg.distanceSq(px, py);

    try testing.expectApproxEqAbs(result.distance_sq, dist * dist, 1e-5);
    try testing.expectApproxEqAbs(result.t, 0.5, 1e-5);
}

test "multiple points have same behavior" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 0);
    const seg = Segment.init(start, end);

    // Test 4 different x positions, same y
    const positions = [_]struct { x: f32, expected_dist_sq: f32, expected_t: f32 }{
        .{ .x = 0, .expected_dist_sq = 9, .expected_t = 0 }, // at start, dist = 3
        .{ .x = 5, .expected_dist_sq = 9, .expected_t = 0.5 }, // at middle, dist = 3
        .{ .x = 10, .expected_dist_sq = 9, .expected_t = 1 }, // at end, dist = 3
        .{ .x = 15, .expected_dist_sq = 34, .expected_t = 1 }, // 5^2 + 3^2 = 34, clamped to end
    };

    for (positions) |pos| {
        const result = seg.distanceSq(pos.x, 3);
        try testing.expectApproxEqAbs(result.distance_sq, pos.expected_dist_sq, 1e-6);
        try testing.expectApproxEqAbs(result.t, pos.expected_t, 1e-6);
    }
}
