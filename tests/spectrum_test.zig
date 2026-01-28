const std = @import("std");
const watchface = @import("watchface");

const spectrum = watchface.spectrum;
const triangle = watchface.triangle;
const circle = watchface.circle;
const clock = watchface.clock;
const vec2 = watchface.vec2;

fn expectNear(actual: f32, expected: f32, tolerance: f32) !void {
    const diff = @abs(actual - expected);
    if (diff > tolerance) {
        std.debug.print("Expected {} to be near {} (tolerance {}), diff was {}\n", .{ actual, expected, tolerance, diff });
        return error.NotNear;
    }
}

fn distance(a: vec2.Vec2, b: vec2.Vec2) f32 {
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    return @sqrt(dx * dx + dy * dy);
}

test "07:40 vertex entry at v2" {
    // Scene setup matching the test in rays_test.c
    const cx: f32 = 200.0;
    const cy: f32 = 200.0;
    const radius: f32 = 180.0;
    const prism_size: f32 = 100.0;

    const center = vec2.xy(cx, cy);
    const prism = triangle.Triangle.isosceles(center, prism_size, 60);
    const boundary = circle.Circle.init(center, radius);

    // 40 minutes
    const minutes: f32 = 40.0;
    const entry = clock.entryPoint(center, radius, minutes);

    // Hour at 7:40 (7 hours + 40 minutes interpolation)
    const hour: f32 = 7.0;
    const hour_angle = clock.hourAngle(hour, minutes);

    const rainbow_spread: f32 = 0.5;

    const paths = spectrum.Paths.compute(
        entry,
        hour_angle,
        rainbow_spread,
        prism,
        boundary,
    );

    // Basic checks
    try std.testing.expect(paths.hits_prism);

    // Get prism vertices
    const v0 = prism.getVertex(0); // apex
    const v2 = prism.getVertex(2); // bottom-left

    // Verify entry point is near v2
    const entry_dist = distance(paths.entry_point, v2);
    try expectNear(entry_dist, 0.0, 2.0);

    // Should need bounce when entry is at vertex with exit on different face
    try std.testing.expect(paths.needs_bounce);

    // Bounce should be at v0 (apex)
    const bounce_dist = distance(paths.bounce_point, v0);
    try expectNear(bounce_dist, 0.0, 0.1);

    // All bands should have valid internal segments
    for (paths.bands) |band| {
        // Both internal segments should exist when needs_bounce is true
        try std.testing.expect(band.internal1 != null);
        try std.testing.expect(band.internal2 != null);
    }
}

test "classify edge position detects vertices" {
    // Test that vertex detection works for u near 0 and 1
    const threshold = spectrum.vertex_threshold;

    // u near 0 should return vertex at start of edge
    const loc0 = spectrum.classifyEdgePosition(1, 0.0);
    try std.testing.expectEqual(@as(u3, 4), loc0); // vertex v1 (3 + 1)

    const loc0_near = spectrum.classifyEdgePosition(1, threshold / 2.0);
    try std.testing.expectEqual(@as(u3, 4), loc0_near);

    // u near 1 should return vertex at end of edge
    const loc1 = spectrum.classifyEdgePosition(1, 1.0);
    try std.testing.expectEqual(@as(u3, 5), loc1); // vertex v2 (3 + 2)

    const loc1_near = spectrum.classifyEdgePosition(1, 1.0 - threshold / 2.0);
    try std.testing.expectEqual(@as(u3, 5), loc1_near);

    // u in middle should return edge index
    const loc_mid = spectrum.classifyEdgePosition(1, 0.5);
    try std.testing.expectEqual(@as(u3, 1), loc_mid);
}

test "bounce logic for entry at v2" {
    const cx: f32 = 200.0;
    const cy: f32 = 200.0;
    const prism_size: f32 = 100.0;

    const center = vec2.xy(cx, cy);
    const prism = triangle.Triangle.isosceles(center, prism_size, 60);

    // Simulate entry at v2 (edge 1, u=1.0)
    const entry_edge: u2 = 1;
    const entry_u: f32 = 1.0;

    // Hour angle pointing toward lower-left (should exit on edge 1)
    const hour_angle: f32 = 2.44;

    const bounce_info = spectrum.computeBounceInfo(
        entry_edge,
        entry_u,
        hour_angle,
        prism,
    );

    // Should need bounce
    try std.testing.expect(bounce_info.needs_bounce);

    // Bounce should be at v0 (vertex 0)
    try std.testing.expectEqual(@as(?u2, 0), bounce_info.bounce_vertex);
}
