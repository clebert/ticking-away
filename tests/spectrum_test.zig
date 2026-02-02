const std = @import("std");
const testing = std.testing;

const lib = @import("lib");
const boundary = lib.boundary;
const clock = lib.clock;
const rainbow = lib.rainbow;
const Prism = lib.Prism;
const spectrum = lib.spectrum;
const vec2 = lib.vec2;

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
    const p = Prism.init(center, prism_size);
    const bnd = boundary.Boundary.init(center, radius);

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
        p,
        bnd,
        false,
    );

    // Basic checks
    try testing.expect(paths.hits_prism);

    // Get prism vertices
    const v0 = p.vertices.get(.apex);
    const v2 = p.vertices.get(.bottom_left);

    // Verify entry point is near v2
    const entry_dist = distance(paths.entry_point, v2);
    try testing.expectApproxEqAbs(entry_dist, 0.0, 2.0);

    // Should need bounce when entry is at vertex with exit on different face
    try testing.expect(paths.needs_bounce);

    // Bounce should be at v0 (apex)
    const bounce_dist = distance(paths.bounce_point, v0);
    try testing.expectApproxEqAbs(bounce_dist, 0.0, 0.1);

    // All colors should have valid internal segments
    for (std.enums.values(rainbow.Color)) |color| {
        const color_path = paths.colors.get(color);
        // Both internal segments should exist when needs_bounce is true
        try testing.expect(color_path.internal1 != null);
        try testing.expect(color_path.internal2 != null);
    }
}

test "classify edge position detects vertices" {
    // Test that vertex detection works for u near 0 and 1
    const threshold = spectrum.vertex_threshold;

    // u near 0 should return vertex at start of edge (bottom edge starts at bottom_right)
    const loc0 = spectrum.classifyEdgePosition(.bottom, 0.0);
    try testing.expectEqual(spectrum.EdgePosition{ .at_vertex = .bottom_right }, loc0);

    const loc0_near = spectrum.classifyEdgePosition(.bottom, threshold / 2.0);
    try testing.expectEqual(spectrum.EdgePosition{ .at_vertex = .bottom_right }, loc0_near);

    // u near 1 should return vertex at end of edge (bottom edge ends at bottom_left)
    const loc1 = spectrum.classifyEdgePosition(.bottom, 1.0);
    try testing.expectEqual(spectrum.EdgePosition{ .at_vertex = .bottom_left }, loc1);

    const loc1_near = spectrum.classifyEdgePosition(.bottom, 1.0 - threshold / 2.0);
    try testing.expectEqual(spectrum.EdgePosition{ .at_vertex = .bottom_left }, loc1_near);

    // u in middle should return edge
    const loc_mid = spectrum.classifyEdgePosition(.bottom, 0.5);
    try testing.expectEqual(spectrum.EdgePosition{ .on_edge = .bottom }, loc_mid);
}

test "bounce logic for entry at v2" {
    const cx: f32 = 200.0;
    const cy: f32 = 200.0;
    const prism_size: f32 = 100.0;

    const center = vec2.xy(cx, cy);
    const p = Prism.init(center, prism_size);

    // Simulate entry at bottom_left (bottom edge, u=1.0)
    const entry_edge: Prism.Edge = .bottom;
    const entry_u: f32 = 1.0;

    // Hour angle pointing toward lower-left (should exit on edge 1)
    const hour_angle: f32 = 2.44;

    const bounce_vertex = spectrum.computeBounceVertex(
        entry_edge,
        entry_u,
        hour_angle,
        p,
    );

    // Should need bounce at apex
    try testing.expectEqual(Prism.Vertex.apex, bounce_vertex.?);
}

test "03:15 exit rays should be valid" {
    const cx: f32 = 200.0;
    const cy: f32 = 200.0;
    const radius: f32 = 180.0;
    const prism_size: f32 = 117.0; // 65% of radius

    const center = vec2.xy(cx, cy);
    const p = Prism.init(center, prism_size);
    const bnd = boundary.Boundary.init(center, radius);

    // 03:15 - minute at 15, hour at 3
    const minutes: f32 = 15.0;
    const hour: f32 = 3.0;
    const entry = clock.entryPoint(center, radius, minutes);
    const hour_angle = clock.hourAngle(hour, minutes);
    const rainbow_spread: f32 = 0.5;

    const paths = spectrum.Paths.compute(
        entry,
        hour_angle,
        rainbow_spread,
        p,
        bnd,
        false,
    );

    // Should hit the prism
    try testing.expect(paths.hits_prism);

    // First and last colors must have exit_ray for gradient to render
    const first_color = paths.colors.get(.red);
    const last_color = paths.colors.get(.violet);

    try testing.expect(first_color.exit_ray != null);
    try testing.expect(last_color.exit_ray != null);

    // Compute the angles that would be used for the external gradient
    const first_border = first_color.exit_ray.?.end;
    const last_border = last_color.exit_ray.?.end;

    const ext_angle_first = std.math.atan2(first_border[1] - cy, first_border[0] - cx);
    const ext_angle_last = std.math.atan2(last_border[1] - cy, last_border[0] - cx);

    // Compute ray_span and edge_margin like watchface.zig does
    const pi = std.math.pi;
    const tau = std.math.tau;
    var ray_span = ext_angle_last - ext_angle_first;
    if (ray_span > pi) ray_span -= tau;
    if (ray_span < -pi) ray_span += tau;

    const edge_margin_factor = 0.5 / @as(f32, @floatFromInt(clock.color_count - 1));
    const edge_margin = ray_span * edge_margin_factor;

    const angle_start = ext_angle_first - edge_margin;
    const angle_end = ext_angle_last + edge_margin;

    // Verify angles don't become problematically negative
    try testing.expect(angle_start > -0.01);
    try testing.expect(angle_end > -0.01);

    // The gradient span should be meaningful
    const span = @abs(ext_angle_first - ext_angle_last);
    try testing.expect(span > 0.1); // At least ~6 degrees
}
