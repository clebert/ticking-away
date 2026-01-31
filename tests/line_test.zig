const std = @import("std");
const testing = std.testing;
const lib = @import("lib");

const line = lib.line;
const vec2 = lib.vec2;

test "point on segment has distance zero" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 0);
    const seg = line.Segment.init(start, end);

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
    const seg = line.Segment.init(start, end);

    // Point 5 units above middle of segment
    const result = seg.distanceSq(5, 5);

    try testing.expectApproxEqAbs(result.distance_sq, 25, 1e-6); // 5^2 = 25
    try testing.expectApproxEqAbs(result.t, 0.5, 1e-6);
}

test "distance to endpoint when outside segment" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 0);
    const seg = line.Segment.init(start, end);

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
    const seg = line.Segment.init(start, end);

    const box = seg.boundingBox(2);
    try testing.expectApproxEqAbs(box.min[0], 3, 1e-6); // 5 - 2
    try testing.expectApproxEqAbs(box.min[1], 8, 1e-6); // 10 - 2
    try testing.expectApproxEqAbs(box.max[0], 17, 1e-6); // 15 + 2
    try testing.expectApproxEqAbs(box.max[1], 22, 1e-6); // 20 + 2
}

test "diagonal segment distance" {
    const start = vec2.xy(0, 0);
    const end = vec2.xy(10, 10);
    const seg = line.Segment.init(start, end);

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
    const seg = line.Segment.init(start, end);

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
