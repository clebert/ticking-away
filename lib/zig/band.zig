const color = @import("color.zig");
const glow = @import("glow.zig");
const line = @import("line.zig");
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
        const glow_width_sq = config.width * config.width;

        for (0..self.height) |local_y| {
            const global_y = self.globalY(local_y);

            for (0..self.width) |x| {
                const point = vec2.xy(@floatFromInt(x), @floatFromInt(global_y));
                const result = segment.distanceSq(point);

                if (result.distance_sq >= glow_width_sq) continue;

                // Normalized distance [0, 1] for falloff
                const distance = @sqrt(result.distance_sq);
                const radial_t = distance / config.width;
                const intensity = config.falloff.apply(radial_t);

                const base_color = switch (config.color) {
                    .uniform => |c| c,
                    .gradient => |g| color.lerp(g.start, g.end, result.t),
                };

                self.pixel(@intCast(x), @intCast(local_y)).* +=
                    @as(color.Color, @splat(intensity)) * base_color;
            }
        }
    }

    inline fn pixel(self: *Context, x: usize, y: usize) *color.Color {
        return &self.buffer[y * self.width + x];
    }

    inline fn globalY(self: *const Context, local_y: usize) usize {
        return self.y_offset + local_y;
    }
};
