const std = @import("std");

const vec2 = @import("vec2.zig");
const triangle = @import("triangle.zig");
const circle = @import("circle.zig");
const ray = @import("ray.zig");
const intersect = @import("intersect.zig");
const clock = @import("clock.zig");

pub const band_count: usize = clock.band_count;
pub const vertex_threshold: f32 = 0.0014;

pub const PathSegment = struct {
    start: vec2.Vec2,
    end: vec2.Vec2,
};

pub const BandPath = struct {
    internal1: ?PathSegment = null,
    internal2: ?PathSegment = null,
    exit_ray: ?PathSegment = null,
    exit_angle: f32 = 0,
    prism_exit: ?vec2.Vec2 = null,
};

pub const BounceInfo = struct {
    needs_bounce: bool,
    bounce_vertex: ?u2,
    bounce_point: vec2.Vec2,
};

pub const Paths = struct {
    entry_ray: ?PathSegment = null,
    entry_point: vec2.Vec2 = vec2.xy(0, 0),
    entry_edge: u2 = 0,
    entry_u: f32 = 0,
    needs_bounce: bool = false,
    bounce_point: vec2.Vec2 = vec2.xy(0, 0),
    bands: [band_count]BandPath = [_]BandPath{.{}} ** band_count,
    hits_prism: bool = false,

    pub fn compute(
        entry: vec2.Vec2,
        hour_angle: f32,
        rainbow_spread: f32,
        prism: triangle.Triangle,
        boundary: circle.Circle,
    ) Paths {
        var paths = Paths{};

        const prism_center = prism.centroid();
        const to_center = vec2.normalize(prism_center - entry);
        const entry_ray = ray.Ray.init(entry, to_center);

        const entry_hit = intersect.rayTriangleEntry(entry_ray, prism) orelse return paths;

        paths.hits_prism = true;
        paths.entry_point = entry_hit.point;
        paths.entry_edge = entry_hit.edge_index;
        paths.entry_u = entry_hit.u;
        paths.entry_ray = .{ .start = entry, .end = entry_hit.point };

        const bounce_info = computeBounceInfo(
            entry_hit.edge_index,
            entry_hit.u,
            hour_angle,
            prism,
        );
        paths.needs_bounce = bounce_info.needs_bounce;
        paths.bounce_point = bounce_info.bounce_point;

        for (0..band_count) |i| {
            const exit_angle = clock.bandExitAngle(hour_angle, rainbow_spread, i);
            paths.bands[i].exit_angle = exit_angle;

            const exit_hit = intersect.rayTriangleExit(prism_center, exit_angle, prism) orelse continue;
            paths.bands[i].prism_exit = exit_hit.point;

            if (bounce_info.needs_bounce) {
                paths.bands[i].internal1 = .{
                    .start = entry_hit.point,
                    .end = bounce_info.bounce_point,
                };
                paths.bands[i].internal2 = .{
                    .start = bounce_info.bounce_point,
                    .end = exit_hit.point,
                };
            } else {
                paths.bands[i].internal1 = .{
                    .start = entry_hit.point,
                    .end = exit_hit.point,
                };
            }

            const exit_ray = ray.Ray.fromAngle(exit_hit.point, exit_angle);
            if (intersect.rayCircle(exit_ray, boundary)) |border_point| {
                paths.bands[i].exit_ray = .{
                    .start = exit_hit.point,
                    .end = border_point,
                };
            }
        }

        return paths;
    }
};

pub fn classifyEdgePosition(edge_index: u2, u: f32) u3 {
    if (u < vertex_threshold) {
        return 3 + edge_index;
    } else if (u > 1.0 - vertex_threshold) {
        return 3 + (edge_index + 1) % 3;
    } else {
        return edge_index;
    }
}

pub fn computeBounceInfo(
    entry_edge: u2,
    entry_u: f32,
    hour_angle: f32,
    prism: triangle.Triangle,
) BounceInfo {
    const entry_location = classifyEdgePosition(entry_edge, entry_u);
    const prism_center = prism.centroid();

    const exit_hit = intersect.rayTriangleExit(prism_center, hour_angle, prism) orelse {
        return .{
            .needs_bounce = false,
            .bounce_vertex = null,
            .bounce_point = vec2.xy(0, 0),
        };
    };

    const exit_location = classifyEdgePosition(exit_hit.edge_index, exit_hit.u);
    const dx = @cos(hour_angle);

    if (entry_location >= 3) {
        const vertex_idx: u2 = @intCast(entry_location - 3);

        if (vertex_idx == 0) {
            const exit_touches_v0 = (exit_location == 3);
            if (exit_touches_v0) {
                const bounce_idx: u2 = if (dx >= 0.0) 2 else 1;
                return .{
                    .needs_bounce = true,
                    .bounce_vertex = bounce_idx,
                    .bounce_point = prism.getVertex(bounce_idx),
                };
            }
        } else {
            const opposite_face: u2 = (vertex_idx + 1) % 3;
            const exit_touches_opposite = (exit_location == opposite_face);
            if (!exit_touches_opposite) {
                const bounce_idx: u2 = (exit_hit.edge_index + 2) % 3;
                return .{
                    .needs_bounce = true,
                    .bounce_vertex = bounce_idx,
                    .bounce_point = prism.getVertex(bounce_idx),
                };
            }
        }
    } else {
        const entry_face: u2 = @intCast(entry_location);
        const same_face_exit = (exit_location == entry_location);
        if (same_face_exit) {
            const bounce_idx: u2 = (entry_face + 2) % 3;
            return .{
                .needs_bounce = true,
                .bounce_vertex = bounce_idx,
                .bounce_point = prism.getVertex(bounce_idx),
            };
        }

        const exit_at_v0 = (exit_location == 3);
        if (exit_at_v0) {
            const bounce_idx: u2 = if (dx >= 0.0) 2 else 1;
            return .{
                .needs_bounce = true,
                .bounce_vertex = bounce_idx,
                .bounce_point = prism.getVertex(bounce_idx),
            };
        }
    }

    return .{
        .needs_bounce = false,
        .bounce_vertex = null,
        .bounce_point = vec2.xy(0, 0),
    };
}
