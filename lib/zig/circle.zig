const range = @import("range.zig");
const vec2 = @import("vec2.zig");

pub const Circle = struct {
    center: vec2.Vec2,
    radius: f32,
    radius_sq: f32,

    pub fn init(center: vec2.Vec2, radius: f32) Circle {
        @setFloatMode(.optimized);
        return .{ .center = center, .radius = radius, .radius_sq = radius * radius };
    }

    /// Returns x-range where scanline y intersects circle
    pub fn scanlineRange(self: Circle, y: f32) ?range.Range {
        @setFloatMode(.optimized);
        const dy = y - self.center[1];
        if (@abs(dy) > self.radius) return null;
        const dx = @sqrt(self.radius_sq - dy * dy);
        return range.Range{
            .x_min = self.center[0] - dx,
            .x_max = self.center[0] + dx,
        };
    }
};
