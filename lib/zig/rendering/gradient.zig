const std = @import("std");
const tau = std.math.tau;
const pi = std.math.pi;
const testing = std.testing;

const color = @import("../color/color.zig");
const palette = @import("../color/palette.zig");
const prism = @import("../geometry/prism.zig");
const band = @import("band.zig");

/// Gradient fill mode.
const Mode = enum {
    /// Fill inside the prism triangle
    internal,
    /// Fill outside prism but inside circle
    external,
};

/// Gradient fill configuration.
pub const Config = struct {
    mode: Mode = .external,
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    angle_start: f32 = 0,
    angle_end: f32 = 0,
    intensity: f32 = 1.0,
    reverse_spectrum: bool = false,
};

/// Geometry context for gradient fill.
pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    prism: prism.Prism,
};

inline fn normalizeAngle(a: f32) f32 {
    @setFloatMode(.optimized);
    var angle = a;
    while (angle < 0) angle += tau;
    while (angle >= tau) angle -= tau;
    return angle;
}

inline fn atan2Approx(y: f32, x: f32) f32 {
    @setFloatMode(.optimized);
    return std.math.atan2(y, x);
}

pub fn render(
    ctx: *band.Context,
    config: Config,
    geometry: Geometry,
    cache: *const palette.Cache,
) void {
    @setFloatMode(.optimized);

    var a1 = normalizeAngle(config.angle_start);
    var a2 = normalizeAngle(config.angle_end);

    var angle_diff = a2 - a1;
    if (angle_diff > pi) angle_diff -= tau;
    if (angle_diff < -pi) angle_diff += tau;

    const angle_span = @abs(angle_diff);
    if (angle_span < 0.001 or angle_span > pi) return;

    const reverse = angle_diff < 0;
    if (reverse) {
        const tmp = a1;
        a1 = a2;
        a2 = tmp;
    }

    const a1_orig = a1;
    const wrap_around = a1 > a2;

    // Expand angle range slightly to avoid edge artifacts.
    // For non-wrap case, clamp to avoid wrapping at 0/tau boundary.
    const eps: f32 = 0.002;
    if (wrap_around) {
        a1 = normalizeAngle(a1 - eps);
        a2 = normalizeAngle(a2 + eps);
    } else {
        a1 = @max(a1 - eps, 0);
        a2 = @min(a2 + eps, tau - 0.0001);
    }

    var x_start: usize = 0;
    var x_end: usize = ctx.width;

    var y_start: usize = 0;
    var y_end: usize = ctx.height;

    const geo_prism = geometry.prism;

    if (config.mode == .internal) {
        const v0 = geo_prism.getVertex(.apex);
        const v1 = geo_prism.getVertex(.bottom_right);
        const v2 = geo_prism.getVertex(.bottom_left);
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
            var pixel_angle = atan2Approx(dy, dx);
            if (pixel_angle < 0) pixel_angle += tau;

            var t: f32 = undefined;
            if (wrap_around) {
                if (pixel_angle < a1 and pixel_angle > a2) continue;
                if (pixel_angle >= a1_orig) {
                    t = (pixel_angle - a1_orig) / angle_span;
                } else {
                    t = (tau - a1_orig + pixel_angle) / angle_span;
                }
            } else {
                if (pixel_angle < a1 or pixel_angle > a2) continue;
                t = (pixel_angle - a1_orig) / angle_span;
            }

            if (reverse) t = 1.0 - t;

            var t_color = (t * @as(f32, palette.band_count) - 0.5) / @as(f32, palette.band_count - 1);
            if (config.reverse_spectrum) t_color = 1.0 - t_color;

            const col = cache.interpolate(t_color);
            const p = &ctx.buffer[local_y * ctx.width + x];
            const intensity_vec: color.Color = @splat(config.intensity);
            p.* = p.* + col * intensity_vec;
        }
    }
}

test "angle normalization edge cases" {
    // Negative angles
    try testing.expectApproxEqAbs(normalizeAngle(-pi), pi, 1e-6);
    try testing.expectApproxEqAbs(normalizeAngle(-tau), 0, 1e-6);

    // Angles >= tau
    try testing.expectApproxEqAbs(normalizeAngle(tau), 0, 1e-6);
    try testing.expectApproxEqAbs(normalizeAngle(tau + pi), pi, 1e-6);

    // Normal angles unchanged
    try testing.expectApproxEqAbs(normalizeAngle(0), 0, 1e-6);
    try testing.expectApproxEqAbs(normalizeAngle(pi), pi, 1e-6);
}

test "wrap around gradient at boundary" {
    // Test that a gradient spanning across 0/tau boundary works
    const p = prism.Prism.init(.{ 50, 50 }, 40);

    var buffer: [100 * 100]color.Color = undefined;
    @memset(&buffer, color.black);

    var ctx = band.Context{
        .buffer = &buffer,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    const cache = palette.Cache.init(.saturated);

    // Gradient that wraps around: from near-tau to past 0
    render(
        &ctx,
        .{
            .mode = .external,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = tau - 0.3, // Near end
            .angle_end = 0.3, // Just past start
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        &cache,
    );

    // Should have rendered some pixels
    var non_black: usize = 0;
    for (buffer) |pixel| {
        if (pixel[0] > 0.001 or pixel[1] > 0.001 or pixel[2] > 0.001) {
            non_black += 1;
        }
    }
    try testing.expect(non_black > 0);
}

test "internal vs external mode" {
    const p = prism.Prism.init(.{ 50, 50 }, 30);
    const cache = palette.Cache.init(.saturated);

    // External mode buffer
    var ext_buffer: [100 * 100]color.Color = undefined;
    @memset(&ext_buffer, color.black);

    var ext_ctx = band.Context{
        .buffer = &ext_buffer,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    render(
        &ext_ctx,
        .{
            .mode = .external,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = 0,
            .angle_end = pi / 2.0,
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        &cache,
    );

    // Internal mode buffer
    var int_buffer: [100 * 100]color.Color = undefined;
    @memset(&int_buffer, color.black);

    var int_ctx = band.Context{
        .buffer = &int_buffer,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    render(
        &int_ctx,
        .{
            .mode = .internal,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = 0,
            .angle_end = pi / 2.0,
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        &cache,
    );

    // Center of prism should be colored in internal mode only
    const cent = p.centroid();
    const cx: usize = @intFromFloat(cent[0]);
    const cy: usize = @intFromFloat(cent[1]);
    const center_idx = cy * 100 + cx;

    // External should have black at prism center (inside prism is excluded)
    const ext_center = ext_buffer[center_idx];
    const ext_sum = ext_center[0] + ext_center[1] + ext_center[2];

    // External mode excludes prism interior
    try testing.expectApproxEqAbs(ext_sum, 0, 0.01);

    // Internal mode fills prism interior (at least partially in the angle range)
    // The center might not be in the 0 to pi/2 angle range, so we check total pixels instead
    var int_non_black: usize = 0;
    for (int_buffer) |pixel| {
        if (pixel[0] > 0.001 or pixel[1] > 0.001 or pixel[2] > 0.001) {
            int_non_black += 1;
        }
    }
    try testing.expect(int_non_black > 0);
}
