const clip = @import("clip.zig");
const color = @import("color.zig");
const glow = @import("glow.zig");
const line = @import("line.zig");
const triangle = @import("triangle.zig");
const vec2 = @import("vec2.zig");

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
                const dist = smoothMinEdgeDist(tri, px, y_center, smooth_k);

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
};

fn smoothMinEdgeDist(tri: triangle.Triangle, px: f32, py: f32, k: f32) f32 {
    @setFloatMode(.optimized);
    const d0 = @sqrt(edgeDistanceSq(tri.getVertex(0), tri.getVertex(1), px, py));
    const d1 = @sqrt(edgeDistanceSq(tri.getVertex(1), tri.getVertex(2), px, py));
    const d2 = @sqrt(edgeDistanceSq(tri.getVertex(2), tri.getVertex(0), px, py));
    return smoothMin(smoothMin(d0, d1, k), d2, k);
}

fn edgeDistanceSq(start: vec2.Vec2, end: vec2.Vec2, px: f32, py: f32) f32 {
    @setFloatMode(.optimized);
    const dir_x = end[0] - start[0];
    const dir_y = end[1] - start[1];
    const len_sq = dir_x * dir_x + dir_y * dir_y;

    if (len_sq < 1e-9) {
        const dx = px - start[0];
        const dy = py - start[1];
        return dx * dx + dy * dy;
    }

    const to_x = px - start[0];
    const to_y = py - start[1];
    const dot_val = to_x * dir_x + to_y * dir_y;
    const t = @min(@max(dot_val / len_sq, 0), 1);

    const proj_x = start[0] + t * dir_x;
    const proj_y = start[1] + t * dir_y;
    const dx = px - proj_x;
    const dy = py - proj_y;

    return dx * dx + dy * dy;
}

fn smoothMin(a: f32, b: f32, k: f32) f32 {
    @setFloatMode(.optimized);
    const h = @max(k - @abs(a - b), 0) / k;
    return @min(a, b) - h * h * k * 0.25;
}
