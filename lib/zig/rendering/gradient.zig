const prism = @import("../geometry/prism.zig");

/// Gradient fill mode.
pub const Mode = enum {
    /// Fill inside the prism triangle
    internal,
    /// Fill outside prism but inside circle
    external,
};

/// Gradient fill configuration.
pub const Config = struct {
    mode: Mode = .external,
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    angle_start: f32 = 0,
    angle_end: f32 = 0,
    intensity: f32 = 1.0,
    reverse_spectrum: bool = false,
};

/// Geometry context for gradient fill.
pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    prism: prism.Prism,
};
