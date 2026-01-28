const std = @import("std");

const color = @import("../color.zig");
const palette = @import("../palette.zig");
const triangle = @import("../triangle.zig");

const tau = std.math.tau;
const pi = std.math.pi;

/// Gradient fill mode.
pub const Mode = enum {
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
    prism: triangle.Triangle,
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

/// Draw continuous gradient fill.
pub fn drawContinuous(
    buffer: []color.Color,
    width: usize,
    height: usize,
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

    // Expand acceptance range by epsilon
    const eps: f32 = 0.002;
    a1 = normalizeAngle(a1 - eps);
    a2 = normalizeAngle(a2 + eps);

    var x_start: usize = 0;
    var x_end: usize = width;
    var y_start: usize = 0;
    var y_end: usize = height;

    const radius_sq = geometry.radius * geometry.radius;
    const prism = geometry.prism;

    if (config.mode == .internal) {
        // Clip to prism bounding box using vertices
        const v0 = prism.getVertex(0);
        const v1 = prism.getVertex(1);
        const v2 = prism.getVertex(2);
        const min_x = @min(@min(v0[0], v1[0]), v2[0]);
        const max_x = @max(@max(v0[0], v1[0]), v2[0]);
        const min_y = @min(@min(v0[1], v1[1]), v2[1]);
        const max_y = @max(@max(v0[1], v1[1]), v2[1]);

        x_start = @intFromFloat(@max(min_x, 0));
        x_end = @intFromFloat(@min(max_x + 1, @as(f32, @floatFromInt(width))));
        y_start = @intFromFloat(@max(min_y, 0));
        y_end = @intFromFloat(@min(max_y + 1, @as(f32, @floatFromInt(height))));
    }

    for (y_start..y_end) |y| {
        const py = @as(f32, @floatFromInt(y)) + 0.5;

        for (x_start..x_end) |x| {
            const px = @as(f32, @floatFromInt(x)) + 0.5;

            // Mode-specific containment check
            const inside = prism.containsPoint(px, py);

            if (config.mode == .external) {
                const dx = px - geometry.center_x;
                const dy = py - geometry.center_y;
                if (dx * dx + dy * dy > radius_sq) continue;
                if (inside) continue;
            } else {
                if (!inside) continue;
            }

            // Calculate pixel angle
            const dx = px - config.origin_x;
            const dy = py - config.origin_y;
            var pixel_angle = atan2Approx(dy, dx);
            if (pixel_angle < 0) pixel_angle += tau;

            // Compute interpolation t
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

            // Remap t for centered band spacing
            var t_color = (t * @as(f32, palette.band_count) - 0.5) / @as(f32, palette.band_count - 1);

            if (config.reverse_spectrum) t_color = 1.0 - t_color;

            // Interpolate color
            const col = cache.interpolate(t_color);

            // Additive blend
            const idx = y * width + x;
            const intensity_vec: color.Color = @splat(config.intensity);
            buffer[idx] = buffer[idx] + col * intensity_vec;
        }
    }
}

test "gradient angle normalization" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), normalizeAngle(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, pi), normalizeAngle(pi), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, pi), normalizeAngle(-pi), 0.001);
}
