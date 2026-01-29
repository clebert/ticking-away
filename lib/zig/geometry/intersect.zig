const std = @import("std");

const vec2 = @import("../math/vec2.zig");
const ray = @import("ray.zig");
const prism = @import("prism.zig");
const boundary = @import("boundary.zig");

const eps_norm: f32 = 1e-9;
const eps_parallel: f32 = 1e-7;
const eps_rel: f32 = 1e-5;

pub const Hit = struct {
    point: vec2.Vec2,
    t: f32,
    u: f32,
    edge: prism.Edge,
};

pub fn raySegment(
    r: ray.Ray,
    segment_start: vec2.Vec2,
    segment_end: vec2.Vec2,
    eps_t: f32,
    eps_u: f32,
) ?Hit {
    @setFloatMode(.optimized);
    const edge = segment_end - segment_start;
    const perp = vec2.xy(-r.direction[1], r.direction[0]);
    const denom = vec2.dot(edge, perp);

    const edge_len = vec2.length(edge);
    const dir_len = vec2.length(r.direction);
    var eps_denom = eps_parallel * edge_len * dir_len;
    if (eps_denom < eps_norm) eps_denom = eps_norm;

    if (@abs(denom) < eps_denom) return null;

    const v = r.origin - segment_start;
    const cross_ev = edge[0] * v[1] - edge[1] * v[0];
    const t = cross_ev / denom;

    if (t < eps_t) return null;

    const u_raw = vec2.dot(v, perp) / denom;

    if (u_raw < -eps_u or u_raw > 1.0 + eps_u) return null;

    const u = std.math.clamp(u_raw, 0.0, 1.0);
    const u_vec: vec2.Vec2 = @splat(u);
    const point = segment_start + edge * u_vec;

    return .{
        .point = point,
        .t = t,
        .u = u,
        .edge = .right,
    };
}

pub fn rayPrismEntry(r: ray.Ray, tri: prism.Prism) ?Hit {
    @setFloatMode(.optimized);
    const scale = prismScale(tri);
    const eps_t = eps_rel * scale;
    const eps_u = eps_rel;

    var best: ?Hit = null;
    var best_t: f32 = std.math.inf(f32);

    inline for (std.meta.tags(prism.Edge)) |edge| {
        const segment = tri.getEdge(edge);
        if (raySegment(r, segment.start, segment.end, eps_t, eps_u)) |hit| {
            if (hit.t < best_t) {
                best_t = hit.t;
                best = .{
                    .point = hit.point,
                    .t = hit.t,
                    .u = hit.u,
                    .edge = edge,
                };
            }
        }
    }

    return best;
}

pub fn rayPrismExit(origin: vec2.Vec2, angle: f32, tri: prism.Prism) ?Hit {
    @setFloatMode(.optimized);
    const r = ray.Ray.fromAngle(origin, angle);
    const scale = prismScale(tri);
    const eps_t = eps_rel * scale;
    const eps_u = eps_rel;

    var best: ?Hit = null;
    var best_t: f32 = 0.0;

    inline for (std.meta.tags(prism.Edge)) |edge| {
        const segment = tri.getEdge(edge);
        if (raySegment(r, segment.start, segment.end, eps_t, eps_u)) |hit| {
            if (hit.t > best_t) {
                best_t = hit.t;
                best = .{
                    .point = hit.point,
                    .t = hit.t,
                    .u = hit.u,
                    .edge = edge,
                };
            }
        }
    }

    return best;
}

pub fn rayBoundary(r: ray.Ray, circ: boundary.Boundary) ?vec2.Vec2 {
    @setFloatMode(.optimized);
    const oc = r.origin - circ.center;
    const a = vec2.dot(r.direction, r.direction);
    const b = 2.0 * vec2.dot(oc, r.direction);
    const c = vec2.dot(oc, oc) - circ.radius_sq;

    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0) return null;

    const sqrt_disc = @sqrt(discriminant);
    const t1 = (-b - sqrt_disc) / (2.0 * a);
    const t2 = (-b + sqrt_disc) / (2.0 * a);

    const eps_t = eps_rel * circ.radius;
    const t = if (t1 > eps_t) t1 else if (t2 > eps_t) t2 else return null;

    return r.pointAt(t);
}

fn prismScale(tri: prism.Prism) f32 {
    @setFloatMode(.optimized);
    var total: f32 = 0.0;
    inline for (std.meta.tags(prism.Edge)) |edge| {
        const segment = tri.getEdge(edge);
        const delta = segment.end - segment.start;
        total += vec2.length(delta);
    }
    return total / 3.0;
}
