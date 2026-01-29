// Math
pub const range = @import("math/range.zig");
pub const vec2 = @import("math/vec2.zig");

// Geometry
pub const boundary = @import("geometry/boundary.zig");
pub const intersect = @import("geometry/intersect.zig");
pub const prism = @import("geometry/prism.zig");
pub const ray = @import("geometry/ray.zig");
pub const segment = @import("geometry/segment.zig");

// Color
pub const color = @import("color/color.zig");
pub const gamma = @import("color/gamma.zig");
pub const oklab = @import("color/oklab.zig");
pub const palette = @import("color/palette.zig");

// Rendering
pub const band = @import("rendering/band.zig");
pub const clip = @import("rendering/clip.zig");
pub const glow = @import("rendering/glow.zig");
pub const gradient = @import("rendering/gradient.zig");
pub const markers = @import("rendering/markers.zig");

// Effects
pub const effect = @import("effects/effect.zig");
pub const grain = @import("effects/grain.zig");
pub const vignette = @import("effects/vignette.zig");

// Dither
pub const dither = @import("dither/dither.zig");
pub const error_diffusion = @import("dither/error_diffusion.zig");
pub const ordered = @import("dither/ordered.zig");

// Pipeline
pub const pipeline = @import("pipeline/pipeline.zig");
pub const postprocess = @import("pipeline/postprocess.zig");
pub const output = @import("pipeline/output.zig");

// Domain
pub const clock = @import("clock.zig");
pub const compat = @import("compat.zig");
pub const scene = @import("scene.zig");
pub const spectrum = @import("spectrum.zig");
