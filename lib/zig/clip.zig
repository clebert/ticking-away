const circle = @import("circle.zig");
const range = @import("range.zig");
const triangle = @import("triangle.zig");

pub const Region = union(enum) {
    triangle: *const triangle.Triangle,
    circle: *const circle.Circle,

    pub fn scanlineRange(self: Region, y: f32) ?range.Range {
        return switch (self) {
            .triangle => |t| t.scanlineRange(y),
            .circle => |c| c.scanlineRange(y),
        };
    }
};
