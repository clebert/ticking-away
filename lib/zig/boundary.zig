const frame = @import("frame.zig");
const vec2 = @import("vec2.zig");

pub const Boundary = struct {
    center: vec2.Vec2,
    radius: f32,

    pub fn init(center: vec2.Vec2, radius: f32) Boundary {
        return .{ .center = center, .radius = radius };
    }

    pub fn scanlineRange(self: Boundary, y: f32) ?frame.Range {
        const dy = y - self.center[1];
        if (@abs(dy) > self.radius) return null;
        const dx = @sqrt(self.radius * self.radius - dy * dy);
        return frame.Range{
            .x_min = self.center[0] - dx,
            .x_max = self.center[0] + dx,
        };
    }
};
