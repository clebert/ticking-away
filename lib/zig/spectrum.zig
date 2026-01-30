const std = @import("std");
const testing = std.testing;

const clock = @import("clock.zig");
const boundary = @import("geometry/boundary.zig");
const intersect = @import("geometry/intersect.zig");
const prism = @import("geometry/prism.zig");
const ray = @import("geometry/ray.zig");
const trig = @import("math/trig.zig");
const vec2 = @import("math/vec2.zig");

pub const vertex_threshold: f32 = 0.0014;

pub const PathSegment = struct {
    start: vec2.Vec2,
    end: vec2.Vec2,
};

const BandPath = struct {
    internal1: ?PathSegment = null,
    internal2: ?PathSegment = null,
    exit_ray: ?PathSegment = null,
    exit_angle: f32 = 0,
    prism_exit: ?vec2.Vec2 = null,
};

pub const Paths = struct {
    entry_ray: ?PathSegment = null,
    entry_point: vec2.Vec2 = vec2.xy(0, 0),
    entry_edge: prism.Edge = .right,
    entry_u: f32 = 0,
    needs_bounce: bool = false,
    bounce_point: vec2.Vec2 = vec2.xy(0, 0),
    bands: [clock.band_count]BandPath = [_]BandPath{.{}} ** clock.band_count,
    hits_prism: bool = false,

    pub fn compute(
        entry: vec2.Vec2,
        hour_angle: f32,
        rainbow_spread: f32,
        p: prism.Prism,
        b: boundary.Boundary,
    ) Paths {
        var paths = Paths{};

        const prism_center = p.centroid();
        const to_center = vec2.normalize(prism_center - entry);
        const entry_ray = ray.Ray.init(entry, to_center);

        const entry_hit = intersect.rayPrismEntry(entry_ray, p) orelse return paths;

        paths.hits_prism = true;
        paths.entry_point = entry_hit.point;
        paths.entry_edge = entry_hit.edge;
        paths.entry_u = entry_hit.u;
        paths.entry_ray = .{ .start = entry, .end = entry_hit.point };

        const bounce_vertex = computeBounceVertex(
            entry_hit.edge,
            entry_hit.u,
            hour_angle,
            p,
        );
        paths.needs_bounce = bounce_vertex != null;
        const bounce_point = if (bounce_vertex) |v| p.vertices.get(v) else vec2.xy(0, 0);
        paths.bounce_point = bounce_point;

        for (0..clock.band_count) |i| {
            const exit_angle = clock.bandExitAngle(hour_angle, rainbow_spread, i);
            paths.bands[i].exit_angle = exit_angle;

            const exit_hit = intersect.rayPrismExit(prism_center, exit_angle, p) orelse continue;
            paths.bands[i].prism_exit = exit_hit.point;

            if (bounce_vertex) |_| {
                paths.bands[i].internal1 = .{
                    .start = entry_hit.point,
                    .end = bounce_point,
                };
                paths.bands[i].internal2 = .{
                    .start = bounce_point,
                    .end = exit_hit.point,
                };
            } else {
                paths.bands[i].internal1 = .{
                    .start = entry_hit.point,
                    .end = exit_hit.point,
                };
            }

            const exit_ray = ray.Ray.fromAngle(exit_hit.point, exit_angle);
            if (intersect.rayBoundary(exit_ray, b)) |border_point| {
                paths.bands[i].exit_ray = .{
                    .start = exit_hit.point,
                    .end = border_point,
                };
            }
        }

        return paths;
    }
};

pub const EdgePosition = union(enum) {
    on_edge: prism.Edge,
    at_vertex: prism.Vertex,
};

pub fn classifyEdgePosition(edge: prism.Edge, u: f32) EdgePosition {
    if (u < vertex_threshold) {
        return .{ .at_vertex = edge.startVertex() };
    } else if (u > 1.0 - vertex_threshold) {
        return .{ .at_vertex = edge.endVertex() };
    } else {
        return .{ .on_edge = edge };
    }
}

pub fn computeBounceVertex(
    entry_edge: prism.Edge,
    entry_u: f32,
    hour_angle: f32,
    p: prism.Prism,
) ?prism.Vertex {
    const entry_pos = classifyEdgePosition(entry_edge, entry_u);
    const prism_center = p.centroid();

    const exit_hit = intersect.rayPrismExit(prism_center, hour_angle, p) orelse return null;

    const exit_pos = classifyEdgePosition(exit_hit.edge, exit_hit.u);
    const dx = trig.cos(hour_angle);

    switch (entry_pos) {
        .at_vertex => |entry_vertex| {
            if (entry_vertex == .apex) {
                // Entry at apex: check if exit touches apex
                const exit_touches_apex = switch (exit_pos) {
                    .at_vertex => |v| v == .apex,
                    .on_edge => |e| e == .right or e == .left,
                };
                if (exit_touches_apex) {
                    return if (dx >= 0.0) .bottom_left else .bottom_right;
                }
            } else {
                // Entry at bottom_right or bottom_left
                const opposite_edge = entry_vertex.oppositeEdge();

                // Check if exit touches the opposite edge (including vertices)
                const exit_touches_opposite = switch (exit_pos) {
                    .at_vertex => |v| opposite_edge.touchesVertex(v),
                    .on_edge => |e| e == opposite_edge,
                };

                if (!exit_touches_opposite) {
                    return exit_hit.edge.oppositeVertex();
                }
            }
        },
        .on_edge => |classified_entry_edge| {
            // Entry on an edge
            const same_edge_exit = switch (exit_pos) {
                .on_edge => |e| e == classified_entry_edge,
                .at_vertex => false,
            };

            if (same_edge_exit) {
                return classified_entry_edge.oppositeVertex();
            }

            // Exit at apex: only bounce if entry edge touches apex
            const exit_at_apex = switch (exit_pos) {
                .at_vertex => |v| v == .apex,
                .on_edge => false,
            };
            if (exit_at_apex) {
                const entry_touches_apex = classified_entry_edge == .right or classified_entry_edge == .left;
                if (entry_touches_apex) {
                    return if (dx >= 0.0) .bottom_left else .bottom_right;
                }
            }
        },
    }

    return null;
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
    const p = prism.Prism.init(center, prism_size);
    const bnd = boundary.Boundary.init(center, radius);

    // 40 minutes
    const minutes: f32 = 40.0;
    const entry = clock.entryPoint(center, radius, minutes);

    // Hour at 7:40 (7 hours + 40 minutes interpolation)
    const hour: f32 = 7.0;
    const hour_angle = clock.hourAngle(hour, minutes);

    const rainbow_spread: f32 = 0.5;

    const paths = Paths.compute(
        entry,
        hour_angle,
        rainbow_spread,
        p,
        bnd,
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

    // All bands should have valid internal segments
    for (paths.bands) |band| {
        // Both internal segments should exist when needs_bounce is true
        try testing.expect(band.internal1 != null);
        try testing.expect(band.internal2 != null);
    }
}

test "classify edge position detects vertices" {
    // Test that vertex detection works for u near 0 and 1
    const threshold = vertex_threshold;

    // u near 0 should return vertex at start of edge (bottom edge starts at bottom_right)
    const loc0 = classifyEdgePosition(.bottom, 0.0);
    try testing.expectEqual(EdgePosition{ .at_vertex = .bottom_right }, loc0);

    const loc0_near = classifyEdgePosition(.bottom, threshold / 2.0);
    try testing.expectEqual(EdgePosition{ .at_vertex = .bottom_right }, loc0_near);

    // u near 1 should return vertex at end of edge (bottom edge ends at bottom_left)
    const loc1 = classifyEdgePosition(.bottom, 1.0);
    try testing.expectEqual(EdgePosition{ .at_vertex = .bottom_left }, loc1);

    const loc1_near = classifyEdgePosition(.bottom, 1.0 - threshold / 2.0);
    try testing.expectEqual(EdgePosition{ .at_vertex = .bottom_left }, loc1_near);

    // u in middle should return edge
    const loc_mid = classifyEdgePosition(.bottom, 0.5);
    try testing.expectEqual(EdgePosition{ .on_edge = .bottom }, loc_mid);
}

test "bounce logic for entry at v2" {
    const cx: f32 = 200.0;
    const cy: f32 = 200.0;
    const prism_size: f32 = 100.0;

    const center = vec2.xy(cx, cy);
    const p = prism.Prism.init(center, prism_size);

    // Simulate entry at bottom_left (bottom edge, u=1.0)
    const entry_edge: prism.Edge = .bottom;
    const entry_u: f32 = 1.0;

    // Hour angle pointing toward lower-left (should exit on edge 1)
    const hour_angle: f32 = 2.44;

    const bounce_vertex = computeBounceVertex(
        entry_edge,
        entry_u,
        hour_angle,
        p,
    );

    // Should need bounce at apex
    try testing.expectEqual(prism.Vertex.apex, bounce_vertex.?);
}

test "03:15 exit rays should be valid" {
    const cx: f32 = 200.0;
    const cy: f32 = 200.0;
    const radius: f32 = 180.0;
    const prism_size: f32 = 117.0; // 65% of radius

    const center = vec2.xy(cx, cy);
    const p = prism.Prism.init(center, prism_size);
    const bnd = boundary.Boundary.init(center, radius);

    // 03:15 - minute at 15, hour at 3
    const minutes: f32 = 15.0;
    const hour: f32 = 3.0;
    const entry = clock.entryPoint(center, radius, minutes);
    const hour_angle = clock.hourAngle(hour, minutes);
    const rainbow_spread: f32 = 0.5;

    const paths = Paths.compute(
        entry,
        hour_angle,
        rainbow_spread,
        p,
        bnd,
    );

    // Should hit the prism
    try testing.expect(paths.hits_prism);

    // First and last bands must have exit_ray for gradient to render
    const first_band = paths.bands[0];
    const last_band = paths.bands[clock.band_count - 1];

    try testing.expect(first_band.exit_ray != null);
    try testing.expect(last_band.exit_ray != null);

    // Compute the angles that would be used for the external gradient
    const first_border = first_band.exit_ray.?.end;
    const last_border = last_band.exit_ray.?.end;

    const ext_angle_first = trig.atan2(first_border[1] - cy, first_border[0] - cx);
    const ext_angle_last = trig.atan2(last_border[1] - cy, last_border[0] - cx);

    // Compute ray_span and edge_margin like scene.zig does
    const pi = std.math.pi;
    const tau = std.math.tau;
    var ray_span = ext_angle_last - ext_angle_first;
    if (ray_span > pi) ray_span -= tau;
    if (ray_span < -pi) ray_span += tau;

    const edge_margin_factor = 0.5 / @as(f32, @floatFromInt(clock.band_count - 1));
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
