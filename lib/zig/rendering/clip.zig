const boundary = @import("../geometry/boundary.zig");
const prism = @import("../geometry/prism.zig");
const scanline = @import("scanline.zig");

pub const Region = union(enum) {
    prism: *const prism.Prism,
    boundary: *const boundary.Boundary,

    pub fn scanlineRange(self: Region, y: f32) ?scanline.Range {
        return switch (self) {
            .prism => |p| p.scanlineRange(y),
            .boundary => |b| b.scanlineRange(y),
        };
    }
};
