const boundary = @import("boundary.zig");
const prism = @import("prism.zig");
const frame = @import("frame.zig");

pub const Region = union(enum) {
    prism: *const prism.Prism,
    boundary: *const boundary.Boundary,

    pub fn scanlineRange(self: Region, y: f32) ?frame.Range {
        return switch (self) {
            .prism => |p| p.scanlineRange(y),
            .boundary => |b| b.scanlineRange(y),
        };
    }
};
