const std = @import("std");
const watchface = @import("watchface");

const triangle = watchface.triangle;
const vec2 = watchface.vec2;

fn expectNear(actual: f32, expected: f32, tolerance: f32) !void {
    const diff = @abs(actual - expected);
    if (diff > tolerance) {
        std.debug.print("Expected {} to be near {} (tolerance {}), diff was {}\n", .{ actual, expected, tolerance, diff });
        return error.NotNear;
    }
}

test "containsPoint inside triangle" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // Centroid should be inside
    const inside = tri.containsPoint(5, 3.33);
    try std.testing.expect(inside);
}

test "containsPoint outside triangle" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // Point clearly outside
    const inside = tri.containsPoint(-5, 5);
    try std.testing.expect(!inside);

    // Point above triangle
    const inside2 = tri.containsPoint(5, 15);
    try std.testing.expect(!inside2);
}

test "containsPoint on edge" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // Point on bottom edge
    const inside = tri.containsPoint(5, 0);
    try std.testing.expect(inside);
}

test "containsPoint multiple points" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // 4 points: inside, outside left, outside right, outside top
    try std.testing.expect(tri.containsPoint(5, 3)); // center inside
    try std.testing.expect(!tri.containsPoint(-5, 5)); // left outside
    try std.testing.expect(!tri.containsPoint(15, 5)); // right outside
    try std.testing.expect(!tri.containsPoint(5, 15)); // top outside
}

test "scanlineRange returns correct bounds" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // Middle scanline (y=5)
    const range = tri.scanlineRange(5);
    try std.testing.expect(range != null);

    const r = range.?;
    // At y=5, the triangle spans from about x=2.5 to x=7.5
    try expectNear(r.x_min, 2.5, 0.1);
    try expectNear(r.x_max, 7.5, 0.1);
}

test "scanlineRange outside triangle returns null" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // Above triangle
    const range1 = tri.scanlineRange(-1);
    try std.testing.expect(range1 == null);

    // Below triangle
    const range2 = tri.scanlineRange(11);
    try std.testing.expect(range2 == null);
}

test "scanlineRange at vertices" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // At bottom (y=0)
    const range_bottom = tri.scanlineRange(0);
    try std.testing.expect(range_bottom != null);
    try expectNear(range_bottom.?.x_min, 0, 0.1);
    try expectNear(range_bottom.?.x_max, 10, 0.1);

    // At top (y=10)
    const range_top = tri.scanlineRange(10);
    try std.testing.expect(range_top != null);
    try expectNear(range_top.?.x_min, 5, 0.1);
    try expectNear(range_top.?.x_max, 5, 0.1);
}

test "minEdgeDistanceSq at centroid" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    const centroid = tri.centroid();
    const dist_sq = tri.minEdgeDistanceSq(centroid[0], centroid[1]);

    // Distance should be positive
    try std.testing.expect(dist_sq > 0);
}

test "minEdgeDistanceSq on edge" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    // Point on bottom edge (v0-v1)
    const dist_sq = tri.minEdgeDistanceSq(5, 0);

    // Distance to edge 0 (v0-v1) should be 0
    try expectNear(dist_sq, 0, 1e-6);
}

test "isosceles creates symmetric triangle" {
    const center = vec2.xy(100, 100);
    const base = 50.0;
    const tri = triangle.Triangle.isosceles(center, base, 60);

    const cent = tri.centroid();
    try expectNear(cent[0], 100, 1);
    try expectNear(cent[1], 100, 1);

    // Check symmetry: v1 and v2 should be equidistant from center
    const v1 = tri.getVertex(1);
    const v2 = tri.getVertex(2);
    const d1 = @sqrt((v1[0] - center[0]) * (v1[0] - center[0]) + (v1[1] - center[1]) * (v1[1] - center[1]));
    const d2 = @sqrt((v2[0] - center[0]) * (v2[0] - center[0]) + (v2[1] - center[1]) * (v2[1] - center[1]));
    try expectNear(d1, d2, 0.1);
}

test "minY and maxY" {
    const v0 = vec2.xy(0, 5);
    const v1 = vec2.xy(10, 15);
    const v2 = vec2.xy(5, 25);
    const tri = triangle.Triangle.init(v0, v1, v2);

    try expectNear(tri.minY(), 5, 1e-6);
    try expectNear(tri.maxY(), 25, 1e-6);
}

test "getVertex returns correct vertices" {
    const v0 = vec2.xy(0, 0);
    const v1 = vec2.xy(10, 0);
    const v2 = vec2.xy(5, 10);
    const tri = triangle.Triangle.init(v0, v1, v2);

    const got0 = tri.getVertex(0);
    const got1 = tri.getVertex(1);
    const got2 = tri.getVertex(2);

    try expectNear(got0[0], 0, 1e-6);
    try expectNear(got0[1], 0, 1e-6);
    try expectNear(got1[0], 10, 1e-6);
    try expectNear(got1[1], 0, 1e-6);
    try expectNear(got2[0], 5, 1e-6);
    try expectNear(got2[1], 10, 1e-6);
}
