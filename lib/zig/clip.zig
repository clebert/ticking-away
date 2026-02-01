const boundary = @import("boundary.zig");
const frame = @import("frame.zig");
const Prism = @import("Prism.zig");

pub const Region = union(enum) {
    prism: *const Prism,
    boundary: *const boundary.Boundary,

    pub fn scanlineRange(self: Region, y: f32) ?frame.Range {
        return switch (self) {
            .prism => |p| p.scanlineRange(y),
            .boundary => |b| b.scanlineRange(y),
        };
    }
};
