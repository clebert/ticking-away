const std = @import("std");
const tau = std.math.tau;
const pi = std.math.pi;

const color = @import("../color/color.zig");
const gradient = @import("gradient.zig");
const palette = @import("../color/palette.zig");

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

pub const Context = struct {
    buffer: []color.Color,
    width: usize,
    height: usize,
    y_offset: usize,
    total_height: usize,

    pub fn clear(self: *Context) void {
        @memset(self.buffer, color.black);
    }

    pub fn clearWithBackground(self: *Context, cx: f32, cy: f32, radius: f32) void {
        @setFloatMode(.optimized);
        const r2 = radius * radius;

        for (0..self.height) |local_y| {
            const global_y = self.globalY(local_y);
            const y: f32 = @floatFromInt(global_y);
            const dy = y - cy;
            const dy2 = dy * dy;

            for (0..self.width) |x| {
                const x_f: f32 = @floatFromInt(x);
                const dx = x_f - cx;
                const dist2 = dx * dx + dy2;

                self.pixel(x, local_y).* = if (dist2 <= r2) color.black else color.white;
            }
        }
    }

    inline fn pixel(self: *Context, x: usize, y: usize) *color.Color {
        return &self.buffer[y * self.width + x];
    }

    inline fn globalY(self: *const Context, local_y: usize) usize {
        return self.y_offset + local_y;
    }

    pub fn renderGradient(
        self: *Context,
        config: gradient.Config,
        geometry: gradient.Geometry,
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
        var x_end: usize = self.width;

        var y_start: usize = 0;
        var y_end: usize = self.height;

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
            x_end = @intFromFloat(@min(max_x + 1, @as(f32, @floatFromInt(self.width))));

            const band_start_f: f32 = @floatFromInt(self.y_offset);
            const band_end_f: f32 = @floatFromInt(self.y_offset + self.height);

            if (max_y < band_start_f or min_y > band_end_f) return;

            y_start = if (min_y <= band_start_f) 0 else @intFromFloat(min_y - band_start_f);
            y_end = if (max_y >= band_end_f) self.height else @min(self.height, @as(usize, @intFromFloat(max_y - band_start_f)) + 1);
        }

        const radius_sq = geometry.radius * geometry.radius;

        for (y_start..y_end) |local_y| {
            const global_y = self.globalY(local_y);
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
                const p = self.pixel(x, local_y);
                const intensity_vec: color.Color = @splat(config.intensity);
                p.* = p.* + col * intensity_vec;
            }
        }
    }
};
