const boundary = @import("../geometry/boundary.zig");
const range = @import("../math/range.zig");
const prism = @import("../geometry/prism.zig");

pub const Region = union(enum) {
    prism: *const prism.Prism,
    boundary: *const boundary.Boundary,

    pub fn scanlineRange(self: Region, y: f32) ?range.Range {
        return switch (self) {
            .prism => |p| p.scanlineRange(y),
            .boundary => |b| b.scanlineRange(y),
        };
    }
};
