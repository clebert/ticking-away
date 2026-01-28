const std = @import("std");

const watchface = @import("watchface");
const Range = watchface.range.Range;
const Triangle = watchface.triangle.Triangle;

test "render horizontal glow line" {
    const WIDTH = 100;
    const HEIGHT = 50;

    var buffer: [WIDTH * HEIGHT]watchface.color.Color = undefined;

    var ctx = watchface.band.Context{
        .buffer = &buffer,
        .width = WIDTH,
        .height = HEIGHT,
        .y_offset = 0,
        .total_height = HEIGHT,
    };

    const segment = watchface.line.Segment.init(
        watchface.vec2.xy(0, HEIGHT / 2),
        watchface.vec2.xy(WIDTH, HEIGHT / 2),
    );

    const config = watchface.glow.Config{
        .width = 10,
        .falloff = .quadratic,
        .color = .{ .uniform = watchface.color.rgba(1, 1, 1, 1) },
    };

    ctx.clear();
    ctx.renderGlowLine(segment, config);

    // Center pixel (on the line) should be bright
    const center = buffer[(HEIGHT / 2) * WIDTH + (WIDTH / 2)];
    try std.testing.expect(center[0] > 0.9);

    // Edge pixel (far from line) should be dim
    const edge = buffer[0 * WIDTH + (WIDTH / 2)];
    try std.testing.expect(edge[0] < 0.1);
}

test "glow falloff types" {
    const Falloff = watchface.glow.Falloff;

    // At center (t=0), all falloffs should be 1.0
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.linear.apply(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.quadratic.apply(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.cubic.apply(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.exponential.apply(0), 0.001);

    // At edge (t=1), all falloffs should be 0.0
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.linear.apply(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.quadratic.apply(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.cubic.apply(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.exponential.apply(1), 0.001);

    // At midpoint (t=0.5): linear=0.5, quadratic=0.25, cubic=0.125
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), Falloff.linear.apply(0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), Falloff.quadratic.apply(0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), Falloff.cubic.apply(0.5), 0.001);
}

test "segment distance calculation" {
    // Horizontal segment from (0, 10) to (100, 10)
    const seg = watchface.line.Segment.init(
        watchface.vec2.xy(0, 10),
        watchface.vec2.xy(100, 10),
    );

    // Point directly above middle of segment
    const result1 = seg.distanceSq(watchface.vec2.xy(50, 15));
    try std.testing.expectApproxEqAbs(@as(f32, 25), result1.distance_sq, 0.001); // 5² = 25
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result1.t, 0.001);

    // Point at segment start
    const result2 = seg.distanceSq(watchface.vec2.xy(0, 10));
    try std.testing.expectApproxEqAbs(@as(f32, 0), result2.distance_sq, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result2.t, 0.001);

    // Point before segment start (should clamp to start)
    const result3 = seg.distanceSq(watchface.vec2.xy(-10, 10));
    try std.testing.expectApproxEqAbs(@as(f32, 100), result3.distance_sq, 0.001); // 10² = 100
    try std.testing.expectApproxEqAbs(@as(f32, 0), result3.t, 0.001);
}

test "degenerate segment (zero length)" {
    // A segment where start == end (single point)
    const point_seg = watchface.line.Segment.init(
        watchface.vec2.xy(10, 10),
        watchface.vec2.xy(10, 10),
    );

    // inv_len_sq should be 0 for degenerate segments
    try std.testing.expectEqual(@as(f32, 0), point_seg.inv_len_sq);

    // Distance from the point should work correctly
    const result1 = point_seg.distanceSq(watchface.vec2.xy(10, 15));
    try std.testing.expectApproxEqAbs(@as(f32, 25), result1.distance_sq, 0.001); // 5² = 25
    try std.testing.expectApproxEqAbs(@as(f32, 0), result1.t, 0.001); // t clamped to 0

    // Distance from the exact point should be 0
    const result2 = point_seg.distanceSq(watchface.vec2.xy(10, 10));
    try std.testing.expectApproxEqAbs(@as(f32, 0), result2.distance_sq, 0.001);

    // Test rendering with degenerate segment doesn't crash
    const WIDTH = 20;
    const HEIGHT = 20;
    var buffer: [WIDTH * HEIGHT]watchface.color.Color = undefined;

    var ctx = watchface.band.Context{
        .buffer = &buffer,
        .width = WIDTH,
        .height = HEIGHT,
        .y_offset = 0,
        .total_height = HEIGHT,
    };

    ctx.clear();
    ctx.renderGlowLine(point_seg, .{
        .width = 5,
        .falloff = .quadratic,
        .color = .{ .uniform = watchface.color.rgba(1, 1, 1, 1) },
    });

    // Pixel at the point location should have some brightness
    const center = buffer[10 * WIDTH + 10];
    try std.testing.expect(center[0] > 0.5);
}

test "range intersection" {
    const a = Range{ .x_min = 0, .x_max = 10 };
    const b = Range{ .x_min = 5, .x_max = 15 };

    const result = a.intersect(b);
    try std.testing.expect(result != null);
    try std.testing.expectApproxEqAbs(@as(f32, 5), result.?.x_min, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.?.x_max, 0.001);
}

test "range no intersection" {
    const a = Range{ .x_min = 0, .x_max = 5 };
    const b = Range{ .x_min = 10, .x_max = 15 };

    const result = a.intersect(b);
    try std.testing.expect(result == null);
}

test "triangle vertex sorting" {
    // Vertices in scrambled order
    const tri = Triangle.init(
        watchface.vec2.xy(50, 100), // bottom
        watchface.vec2.xy(50, 0), // top
        watchface.vec2.xy(0, 50), // mid-left
    );

    // After sorting, top should have smallest y
    try std.testing.expectApproxEqAbs(@as(f32, 0), tri.top[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50), tri.mid[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), tri.bot[1], 0.001);
}

test "triangle scanline range" {
    // Right triangle: (0,0), (100,0), (0,100)
    const tri = Triangle.init(
        watchface.vec2.xy(0, 0),
        watchface.vec2.xy(100, 0),
        watchface.vec2.xy(0, 100),
    );

    // At y=0, the scanline should span from 0 to 100
    const range_top = tri.scanlineRange(0.5);
    try std.testing.expect(range_top != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), range_top.?.x_min, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 100), range_top.?.x_max, 1);

    // At y=50, the scanline should span from 0 to ~50
    const range_mid = tri.scanlineRange(50.5);
    try std.testing.expect(range_mid != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), range_mid.?.x_min, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 50), range_mid.?.x_max, 1);

    // Outside triangle should return null
    try std.testing.expect(tri.scanlineRange(-10) == null);
    try std.testing.expect(tri.scanlineRange(110) == null);
}

test "triangle edge distance" {
    // Equilateral-ish triangle centered at (50, 50)
    const tri = Triangle.init(
        watchface.vec2.xy(50, 0),
        watchface.vec2.xy(100, 87),
        watchface.vec2.xy(0, 87),
    );

    // Point at center should have some distance to all edges
    const center_dist = tri.edgeDistancesSq(watchface.vec2.xy(50, 50));
    try std.testing.expect(center_dist[0] > 0);
    try std.testing.expect(center_dist[1] > 0);
    try std.testing.expect(center_dist[2] > 0);

    // Point exactly on first vertex should have 0 distance to edges that share it
    const vertex_dist = tri.edgeDistancesSq(watchface.vec2.xy(50, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertex_dist[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertex_dist[2], 0.001);
}

test "isosceles triangle creation" {
    const tri = Triangle.isosceles(
        watchface.vec2.xy(100, 100),
        80, // base width
        60, // apex angle
    );

    // Should create a valid triangle
    try std.testing.expect(tri.top[1] < tri.mid[1]);
    try std.testing.expect(tri.mid[1] <= tri.bot[1]);

    // Base vertices should be symmetric around center x
    const base_y = tri.bot[1];
    const mid_range = tri.scanlineRange(base_y - 0.1);
    try std.testing.expect(mid_range != null);
}

test "render prism glow" {
    const WIDTH = 100;
    const HEIGHT = 100;

    var buffer: [WIDTH * HEIGHT]watchface.color.Color = undefined;

    var ctx = watchface.band.Context{
        .buffer = &buffer,
        .width = WIDTH,
        .height = HEIGHT,
        .y_offset = 0,
        .total_height = HEIGHT,
    };

    const tri = Triangle.isosceles(
        watchface.vec2.xy(50, 50),
        60,
        60,
    );

    ctx.clear();
    ctx.renderPrismGlow(
        tri,
        watchface.color.rgba(1, 1, 1, 1),
        15,
        1.0,
        .quadratic,
    );

    // Near an edge (inside triangle) should have glow
    // For isoceles(center=(50,50), base=60, angle=60):
    // - apex at approximately (50, 15)
    // - base corners at approximately (20, 67) and (80, 67)
    // At y=40, triangle spans roughly x=36 to x=64
    // Check point (40, 40) which is ~4 pixels inside left edge
    const near_edge = buffer[40 * WIDTH + 40];
    try std.testing.expect(near_edge[0] > 0.1);

    // Center of triangle should have less glow (farther from edges)
    const center = buffer[40 * WIDTH + 50];
    try std.testing.expect(center[0] <= near_edge[0]);
}
