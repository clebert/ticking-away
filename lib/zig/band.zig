const color = @import("color.zig");
const glow = @import("glow.zig");
const line = @import("line.zig");
const vec2 = @import("vec2.zig");

pub const BandContext = struct {
    buffer: []color.Color,
    width: usize,
    height: usize,
    y_offset: usize,
    total_height: usize,

    pub inline fn pixel(self: *BandContext, x: usize, y: usize) *color.Color {
        return &self.buffer[y * self.width + x];
    }

    pub inline fn globalY(self: *const BandContext, local_y: usize) usize {
        return self.y_offset + local_y;
    }
};

pub fn clear(ctx: *BandContext) void {
    @memset(ctx.buffer, color.black);
}

/// Renders with additive blending - multiple calls accumulate light.
pub fn renderGlowLine(ctx: *BandContext, segment: line.Segment, config: glow.Config) void {
    const glow_width_sq = config.width * config.width;

    for (0..ctx.height) |local_y| {
        const global_y = ctx.globalY(local_y);

        for (0..ctx.width) |x| {
            const point = vec2.xy(@floatFromInt(x), @floatFromInt(global_y));
            const result = line.segmentDistanceSq(segment, point);

            if (result.distance_sq >= glow_width_sq) continue;

            // Normalized distance [0, 1] for falloff
            const distance = @sqrt(result.distance_sq);
            const t = distance / config.width;
            const intensity = config.falloff.apply(t);

            const pixel = ctx.pixel(@intCast(x), @intCast(local_y));
            pixel.* += @as(color.Color, @splat(intensity)) * config.color;
        }
    }
}
