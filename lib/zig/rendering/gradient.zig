const std = @import("std");
const tau = std.math.tau;
const pi = std.math.pi;

const color_space = @import("../color/color_space.zig");
const palette = @import("../color/palette.zig");
const prism = @import("../geometry/prism.zig");
const band = @import("band.zig");

const Mode = enum {
    internal,
    external,
};

pub const Config = struct {
    mode: Mode = .external,
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    angle_start: f32 = 0,
    angle_end: f32 = 0,
    intensity: f32 = 1.0,
    reverse_spectrum: bool = false,
};

pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    prism: prism.Prism,
};

inline fn normalizeAngle(a: f32) f32 {
    return @mod(a, tau);
}

pub fn render(
    ctx: *band.Context,
    config: Config,
    geometry: Geometry,
    cache: *const palette.Cache,
) void {
    const a1_normalized = normalizeAngle(config.angle_start);
    const a2_normalized = normalizeAngle(config.angle_end);

    const angle_diff = blk: {
        var diff = a2_normalized - a1_normalized;
        if (diff > pi) diff -= tau;
        if (diff < -pi) diff += tau;
        break :blk diff;
    };

    const angle_span = @abs(angle_diff);
    if (angle_span < 0.001 or angle_span > pi) return;

    const reverse = angle_diff < 0;
    const a1_sorted = if (reverse) a2_normalized else a1_normalized;
    const a2_sorted = if (reverse) a1_normalized else a2_normalized;

    const a1_orig = a1_sorted;
    const wrap_around = a1_sorted > a2_sorted;

    const eps: f32 = 0.002;
    const a1 = if (wrap_around) normalizeAngle(a1_sorted - eps) else @max(a1_sorted - eps, 0);
    const a2 = if (wrap_around) normalizeAngle(a2_sorted + eps) else @min(a2_sorted + eps, tau - 0.0001);

    var x_start: usize = 0;
    var x_end: usize = ctx.width;

    var y_start: usize = 0;
    var y_end: usize = ctx.height;

    const geo_prism = geometry.prism;

    if (config.mode == .internal) {
        const v0 = geo_prism.vertices.get(.apex);
        const v1 = geo_prism.vertices.get(.bottom_right);
        const v2 = geo_prism.vertices.get(.bottom_left);
        const min_x = @min(@min(v0[0], v1[0]), v2[0]);
        const max_x = @max(@max(v0[0], v1[0]), v2[0]);
        const min_y = @min(@min(v0[1], v1[1]), v2[1]);
        const max_y = @max(@max(v0[1], v1[1]), v2[1]);

        x_start = @intFromFloat(@max(min_x, 0));
        x_end = @intFromFloat(@min(max_x + 1, @as(f32, @floatFromInt(ctx.width))));

        const band_start_f: f32 = @floatFromInt(ctx.y_offset);
        const band_end_f: f32 = @floatFromInt(ctx.y_offset + ctx.height);

        if (max_y < band_start_f or min_y > band_end_f) return;

        y_start = if (min_y <= band_start_f) 0 else @intFromFloat(min_y - band_start_f);
        y_end = if (max_y >= band_end_f) ctx.height else @min(ctx.height, @as(usize, @intFromFloat(max_y - band_start_f)) + 1);
    }

    const radius_sq = geometry.radius * geometry.radius;

    for (y_start..y_end) |local_y| {
        const global_y = ctx.y_offset + local_y;
        const py = @as(f32, @floatFromInt(global_y)) + 0.5;

        for (x_start..x_end) |x| {
            const px = @as(f32, @floatFromInt(x)) + 0.5;

            const inside = geo_prism.containsPoint(px, py);

            if (config.mode == .external) {
                const dx = px - geometry.center_x;
                const dy = py - geometry.center_y;
                if (dx * dx + dy * dy > radius_sq) continue;
                if (inside) continue;
            } else {
                if (!inside) continue;
            }

            const dx = px - config.origin_x;
            const dy = py - config.origin_y;
            var pixel_angle = std.math.atan2(dy, dx);
            if (pixel_angle < 0) pixel_angle += tau;

            const t_raw = blk: {
                if (wrap_around) {
                    if (pixel_angle < a1 and pixel_angle > a2) continue;
                    break :blk if (pixel_angle >= a1_orig)
                        (pixel_angle - a1_orig) / angle_span
                    else
                        (tau - a1_orig + pixel_angle) / angle_span;
                } else {
                    if (pixel_angle < a1 or pixel_angle > a2) continue;
                    break :blk (pixel_angle - a1_orig) / angle_span;
                }
            };

            const t = if (reverse) 1.0 - t_raw else t_raw;

            const band_count_f: f32 = @floatFromInt(palette.band_count);
            const t_color_raw = (t * band_count_f - 0.5) / (band_count_f - 1.0);
            const t_color = if (config.reverse_spectrum) 1.0 - t_color_raw else t_color_raw;

            const col = cache.interpolate(t_color);
            const p = &ctx.buffer[local_y * ctx.width + x];
            const intensity_vec: @Vector(4, f32) = @splat(config.intensity);
            p.vec = p.vec + col.vec * intensity_vec;
        }
    }
}
