const std = @import("std");
const tau = std.math.tau;
const pi = std.math.pi;

const clip = @import("clip.zig");
const color = @import("color/color.zig");
const glow = @import("glow.zig");
const gradient = @import("gradient.zig");
const line = @import("geometry/line.zig");
const palette = @import("color/palette.zig");
const triangle = @import("geometry/triangle.zig");
const vec2 = @import("math/vec2.zig");

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

    pub fn renderGlowLine(
        self: *Context,
        segment: line.Segment,
        config: glow.Config,
        clip_to: ?clip.Region,
        exclude: ?*const triangle.Triangle,
    ) void {
        @setFloatMode(.optimized);
        const glow_width = config.width;
        const glow_width_sq = glow_width * glow_width;

        const bounds = segment.boundingBox(glow_width);
        const y_min = @max(0, @as(isize, @intFromFloat(bounds.min[1])));
        const y_max = @min(@as(isize, @intCast(self.total_height)), @as(isize, @intFromFloat(bounds.max[1])) + 1);
        const x_min = @max(0, @as(isize, @intFromFloat(bounds.min[0])));
        const x_max = @min(@as(isize, @intCast(self.width)), @as(isize, @intFromFloat(bounds.max[0])) + 1);

        if (y_min >= y_max or x_min >= x_max) return;

        const x_start: usize = @intCast(x_min);
        const x_end: usize = @intCast(x_max);

        const band_y_min: isize = @intCast(self.y_offset);
        const band_y_max: isize = @intCast(self.y_offset + self.height);

        if (y_max <= band_y_min or y_min >= band_y_max) return;

        const local_y_start: usize = if (y_min < band_y_min) 0 else @intCast(y_min - band_y_min);
        const local_y_end: usize = if (y_max > band_y_max) self.height else @intCast(y_max - band_y_min);

        for (local_y_start..local_y_end) |local_y| {
            const global_y = self.globalY(local_y);
            const y_f: f32 = @floatFromInt(global_y);
            const y_center = y_f + 0.5;

            var row_x_start = x_start;
            var row_x_end = x_end;
            if (clip_to) |region| {
                const clip_range = region.scanlineRange(y_center) orelse continue;
                row_x_start = @max(row_x_start, @as(usize, @intFromFloat(@max(0, clip_range.x_min))));
                row_x_end = @min(row_x_end, @as(usize, @intFromFloat(clip_range.x_max)) + 1);
                if (row_x_start >= row_x_end) continue;
            }

            for (row_x_start..row_x_end) |x| {
                const px = @as(f32, @floatFromInt(x)) + 0.5;

                if (exclude) |tri| {
                    if (tri.containsPoint(px, y_center)) continue;
                }

                const result = segment.distanceSq(px, y_center);
                if (result.distance_sq >= glow_width_sq) continue;

                const distance = @sqrt(result.distance_sq);
                const radial_t = distance / glow_width;
                const radial_intensity = config.falloff.apply(radial_t);
                const linear_intensity = switch (config.intensity) {
                    .uniform => |v| v,
                    .gradient => |g| g.start + (g.end - g.start) * result.t,
                };
                const intensity = radial_intensity * linear_intensity;
                const base_color = switch (config.color) {
                    .uniform => |c| c,
                    .gradient => |g| color.lerp(g.start, g.end, result.t),
                };

                const p = self.pixel(x, local_y);
                const scale_vec: color.Color = @splat(intensity);
                p.* = p.* + base_color * scale_vec;
            }
        }
    }

    inline fn pixel(self: *Context, x: usize, y: usize) *color.Color {
        return &self.buffer[y * self.width + x];
    }

    inline fn globalY(self: *const Context, local_y: usize) usize {
        return self.y_offset + local_y;
    }

    pub fn renderPrismGlow(
        self: *Context,
        tri: triangle.Triangle,
        glow_color: color.Color,
        glow_width: f32,
        intensity: f32,
        falloff: glow.Falloff,
    ) void {
        @setFloatMode(.optimized);
        const smooth_k = glow_width * 0.5;

        const y_min = @max(self.y_offset, @as(usize, @intFromFloat(@max(0, tri.minY()))));
        const y_max = @min(self.y_offset + self.height, @as(usize, @intFromFloat(tri.maxY())) + 1);

        for (y_min..y_max) |global_y| {
            const local_y = global_y - self.y_offset;
            const y_f: f32 = @floatFromInt(global_y);
            const y_center = y_f + 0.5;

            const tri_range = tri.scanlineRange(y_center) orelse continue;
            const x_start = @max(0, @as(usize, @intFromFloat(tri_range.x_min)));
            const x_end = @min(self.width, @as(usize, @intFromFloat(tri_range.x_max)) + 1);

            for (x_start..x_end) |x| {
                const px = @as(f32, @floatFromInt(x)) + 0.5;
                const dist = tri.smoothEdgeDistance(vec2.xy(px, y_center), smooth_k);

                if (dist < glow_width) {
                    const t = @min(@max(dist / glow_width, 0), 1);
                    const alpha = falloff.apply(t) * intensity;
                    const p = self.pixel(x, local_y);
                    const scale_vec: color.Color = @splat(alpha);
                    p.* = p.* + glow_color * scale_vec;
                }
            }
        }
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

        const prism = geometry.prism;

        if (config.mode == .internal) {
            const v0 = prism.getVertex(.apex);
            const v1 = prism.getVertex(.bottom_right);
            const v2 = prism.getVertex(.bottom_left);
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

                const inside = prism.containsPoint(px, py);

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
