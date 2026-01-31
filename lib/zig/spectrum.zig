const std = @import("std");

const clock = @import("clock.zig");
const boundary = @import("geometry/boundary.zig");
const intersect = @import("geometry/intersect.zig");
const prism = @import("geometry/prism.zig");
const ray = @import("geometry/ray.zig");
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
    const dx = @cos(hour_angle);

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
