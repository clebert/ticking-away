const std = @import("std");
const testing = std.testing;

const lib = @import("lib");
const boundary = lib.boundary;
const intersect = lib.intersect;
const line = lib.line;
const Prism = lib.Prism;
const ray = lib.ray;
const vec2 = lib.vec2;

// Ray-Segment tests

test "ray segment hit middle" {
    // Ray from (0, 5) going right, segment from (10, 0) to (10, 10)
    const r = ray.Ray.init(vec2.xy(0, 5), vec2.xy(1, 0));
    const seg = line.Segment.init(vec2.xy(10, 0), vec2.xy(10, 10));
    const hit = intersect.raySegment(r, seg, 0.001, 0.00001);

    try testing.expect(hit != null);
    try testing.expectApproxEqAbs(hit.?.point[0], 10.0, 0.001);
    try testing.expectApproxEqAbs(hit.?.point[1], 5.0, 0.001);
    try testing.expectApproxEqAbs(hit.?.t, 10.0, 0.001);
    try testing.expectApproxEqAbs(hit.?.u, 0.5, 0.001);
}

test "ray segment hit endpoint" {
    // Ray hitting near start of segment
    const r = ray.Ray.init(vec2.xy(0, 0), vec2.xy(1, 0));
    const seg = line.Segment.init(vec2.xy(10, 0), vec2.xy(10, 10));
    const hit = intersect.raySegment(r, seg, 0.001, 0.00001);

    try testing.expect(hit != null);
    try testing.expectApproxEqAbs(hit.?.u, 0.0, 0.001);
}

test "ray segment miss parallel" {
    // Ray parallel to segment
    const r = ray.Ray.init(vec2.xy(0, 5), vec2.xy(0, 1));
    const seg = line.Segment.init(vec2.xy(10, 0), vec2.xy(10, 10));
    const hit = intersect.raySegment(r, seg, 0.001, 0.00001);

    try testing.expect(hit == null);
}

test "ray segment miss behind" {
    // Ray going away from segment
    const r = ray.Ray.init(vec2.xy(20, 5), vec2.xy(1, 0));
    const seg = line.Segment.init(vec2.xy(10, 0), vec2.xy(10, 10));
    const hit = intersect.raySegment(r, seg, 0.001, 0.00001);

    try testing.expect(hit == null);
}

test "ray segment miss outside" {
    // Ray misses segment entirely (above it)
    const r = ray.Ray.init(vec2.xy(0, 15), vec2.xy(1, 0));
    const seg = line.Segment.init(vec2.xy(10, 0), vec2.xy(10, 10));
    const hit = intersect.raySegment(r, seg, 0.001, 0.00001);

    try testing.expect(hit == null);
}

// Ray-Prism tests

test "prism find entry from left" {
    const p = Prism.init(vec2.xy(200, 200), 100);

    // Ray from left going right toward center
    const r = ray.Ray.init(vec2.xy(100, 200), vec2.xy(1, 0));
    const hit = intersect.rayPrismEntry(r, p);

    try testing.expect(hit != null);
    try testing.expect(hit.?.t > 0.0);
}

test "prism find entry miss" {
    const p = Prism.init(vec2.xy(200, 200), 100);

    // Ray going away from prism
    const r = ray.Ray.init(vec2.xy(100, 100), vec2.xy(-1, 0));
    const hit = intersect.rayPrismEntry(r, p);

    try testing.expect(hit == null);
}

test "prism find exit from center" {
    const p = Prism.init(vec2.xy(200, 200), 100);

    // Ray from center going right (angle = 0)
    const hit = intersect.rayPrismExit(vec2.xy(200, 200), 0.0, p);

    try testing.expect(hit != null);
    try testing.expect(hit.?.t > 0.0);
    try testing.expect(hit.?.point[0] > 200.0); // Should exit to the right
}

test "prism find exit downward" {
    const p = Prism.init(vec2.xy(200, 200), 100);

    // Ray from center going down (angle = PI/2)
    const hit = intersect.rayPrismExit(vec2.xy(200, 200), std.math.pi / 2.0, p);

    try testing.expect(hit != null);
    try testing.expect(hit.?.point[1] > 200.0); // Should exit below center
}

// Ray-Circle tests

test "ray circle hit through center" {
    const circ = boundary.Boundary.init(vec2.xy(100, 0), 50);
    const r = ray.Ray.init(vec2.xy(0, 0), vec2.xy(1, 0));
    const hit = intersect.rayBoundary(r, circ);

    try testing.expect(hit != null);
    try testing.expectApproxEqAbs(hit.?[0], 50.0, 0.1); // First hit at x=50
    try testing.expectApproxEqAbs(hit.?[1], 0.0, 0.1);
}

test "ray circle hit tangent" {
    const circ = boundary.Boundary.init(vec2.xy(100, 0), 50);
    // Ray tangent to circle at (100, 50)
    const r = ray.Ray.init(vec2.xy(0, 50), vec2.xy(1, 0));
    const hit = intersect.rayBoundary(r, circ);

    try testing.expect(hit != null);
    try testing.expectApproxEqAbs(hit.?[0], 100.0, 0.5);
    try testing.expectApproxEqAbs(hit.?[1], 50.0, 0.5);
}

test "ray circle miss" {
    const circ = boundary.Boundary.init(vec2.xy(100, 0), 50);
    // Ray above circle
    const r = ray.Ray.init(vec2.xy(0, 100), vec2.xy(1, 0));
    const hit = intersect.rayBoundary(r, circ);

    try testing.expect(hit == null);
}

test "ray circle from inside" {
    const circ = boundary.Boundary.init(vec2.xy(100, 0), 50);
    // Ray from inside circle
    const r = ray.Ray.init(vec2.xy(100, 0), vec2.xy(1, 0));
    const hit = intersect.rayBoundary(r, circ);

    try testing.expect(hit != null);
    try testing.expectApproxEqAbs(hit.?[0], 150.0, 0.1); // Should exit at far side
}
