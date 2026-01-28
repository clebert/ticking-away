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

    /// Renders with additive blending - multiple calls accumulate light.
    pub fn renderGlowLine(self: *Context, segment: line.Segment, config: glow.Config) void {
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

        const band_y_min = self.y_offset;
        const band_y_max = self.y_offset + self.height;
        const local_y_start = if (y_min < band_y_min) 0 else @as(usize, @intCast(y_min)) - band_y_min;
        const local_y_end = if (y_max > band_y_max) self.height else @as(usize, @intCast(y_max)) - band_y_min;

        const glow_width_sq_vec: @Vector(4, f32) = @splat(glow_width_sq);
        const glow_width_vec: @Vector(4, f32) = @splat(glow_width);

        for (local_y_start..local_y_end) |local_y| {
            const global_y = self.globalY(local_y);
            const y_f: f32 = @floatFromInt(global_y);
            const py: @Vector(4, f32) = @splat(y_f + 0.5);

            // SIMD loop: 4 pixels at a time
            var x = x_start;

            while (x + 4 <= x_end) : (x += 4) {
                const base: @Vector(4, f32) = @splat(@floatFromInt(x));
                const px = base + @Vector(4, f32){ 0.5, 1.5, 2.5, 3.5 };
                const result = segment.distanceSq4(px, py);
                const mask = result.distance_sq < glow_width_sq_vec;

                if (!@reduce(.Or, mask)) continue;

                const distances = @sqrt(result.distance_sq);
                const radial_t = distances / glow_width_vec;

                inline for (0..4) |i| {
                    if (mask[i]) {
                        const intensity = config.falloff.apply(radial_t[i]);

                        const base_color = switch (config.color) {
                            .uniform => |c| c,
                            .gradient => |g| color.lerp(g.start, g.end, result.t[i]),
                        };

                        self.pixel(x + i, local_y).* += @as(color.Color, @splat(intensity)) * base_color;
                    }
                }
            }

            // Scalar tail
            while (x < x_end) : (x += 1) {
                const point = vec2.xy(@as(f32, @floatFromInt(x)) + 0.5, y_f + 0.5);
                const result = segment.distanceSq(point);

                if (result.distance_sq >= glow_width_sq) continue;

                const distance = @sqrt(result.distance_sq);
                const radial_t = distance / glow_width;
                const intensity = config.falloff.apply(radial_t);

                const base_color = switch (config.color) {
                    .uniform => |c| c,
                    .gradient => |g| color.lerp(g.start, g.end, result.t),
                };

                self.pixel(x, local_y).* += @as(color.Color, @splat(intensity)) * base_color;
            }
        }
    }

    inline fn pixel(self: *Context, x: usize, y: usize) *color.Color {
        return &self.buffer[y * self.width + x];
    }

    inline fn globalY(self: *const Context, local_y: usize) usize {
        return self.y_offset + local_y;
    }

    /// Renders glow effect inside a triangle (prism edges)
    pub fn renderPrismGlow(
        self: *Context,
        tri: triangle.Triangle,
        glow_color: color.Color,
        glow_width: f32,
        intensity: f32,
        falloff: glow.Falloff,
    ) void {
        const smooth_k = glow_width * 0.5;

        const y_min = @max(self.y_offset, @as(usize, @intFromFloat(@max(0, tri.minY()))));
        const y_max = @min(self.y_offset + self.height, @as(usize, @intFromFloat(tri.maxY())) + 1);

        for (y_min..y_max) |global_y| {
            const local_y = global_y - self.y_offset;
            const y_f: f32 = @floatFromInt(global_y);

            const tri_range = tri.scanlineRange(y_f + 0.5) orelse continue;
            const x_start = @max(0, @as(usize, @intFromFloat(tri_range.x_min)));
            const x_end = @min(self.width, @as(usize, @intFromFloat(tri_range.x_max)) + 1);

            var x = x_start;
            const py: @Vector(4, f32) = @splat(y_f + 0.5);
            const glow_width_vec: @Vector(4, f32) = @splat(glow_width);
            const smooth_k_vec: @Vector(4, f32) = @splat(smooth_k);

            while (x + 4 <= x_end) : (x += 4) {
                const base: @Vector(4, f32) = @splat(@floatFromInt(x));
                const px = base + @Vector(4, f32){ 0.5, 1.5, 2.5, 3.5 };
                const dist_sq = tri.edgeDistancesSq4(px, py);

                // Vectorized sqrt for all 3 edges × 4 pixels
                const d0 = @sqrt(dist_sq[0]);
                const d1 = @sqrt(dist_sq[1]);
                const d2 = @sqrt(dist_sq[2]);

                // Vectorized smoothMin
                const dist = smoothMin4(smoothMin4(d0, d1, smooth_k_vec), d2, smooth_k_vec);

                // Early exit if all 4 pixels are outside glow radius
                const zero: @Vector(4, f32) = @splat(0);
                const one: @Vector(4, f32) = @splat(1);
                const mask = dist < glow_width_vec;
                if (!@reduce(.Or, mask)) continue;

                const t = @min(@max(dist / glow_width_vec, zero), one);

                inline for (0..4) |i| {
                    if (mask[i]) {
                        const alpha = falloff.apply(t[i]) * intensity;
                        self.pixel(x + i, local_y).* += @as(color.Color, @splat(alpha)) * glow_color;
                    }
                }
            }

            while (x < x_end) : (x += 1) {
                const point = vec2.xy(@as(f32, @floatFromInt(x)) + 0.5, y_f + 0.5);
                const dist_sq = tri.edgeDistancesSq(point);
                const d0 = @sqrt(dist_sq[0]);
                const d1 = @sqrt(dist_sq[1]);
                const d2 = @sqrt(dist_sq[2]);
                const dist = smoothMin(smoothMin(d0, d1, smooth_k), d2, smooth_k);

                if (dist < glow_width) {
                    const t = @min(@max(dist / glow_width, 0), 1);
                    const alpha = falloff.apply(t) * intensity;
                    self.pixel(x, local_y).* += @as(color.Color, @splat(alpha)) * glow_color;
                }
            }
        }
    }
};

fn smoothMin(a: f32, b: f32, k: f32) f32 {
    const h = @max(k - @abs(a - b), 0) / k;
    return @min(a, b) - h * h * k * 0.25;
}

fn smoothMin4(a: @Vector(4, f32), b: @Vector(4, f32), k: @Vector(4, f32)) @Vector(4, f32) {
    const zero: @Vector(4, f32) = @splat(0);
    const quarter: @Vector(4, f32) = @splat(0.25);
    const h = @max(k - @abs(a - b), zero) / k;
    return @min(a, b) - h * h * k * quarter;
}
