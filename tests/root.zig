test {
    // Top-level modules
    _ = @import("clock_test.zig");
    _ = @import("spectrum_test.zig");

    // Color modules
    _ = @import("color/color_space_test.zig");
    _ = @import("color/palette_test.zig");

    // Dither modules
    _ = @import("dither/dither_test.zig");
    _ = @import("dither/error_diffusion_test.zig");
    _ = @import("dither/ordered_test.zig");

    // Effects modules
    _ = @import("effects/grain_test.zig");
    _ = @import("effects/vignette_test.zig");

    // Geometry modules
    _ = @import("geometry/intersect_test.zig");
    _ = @import("geometry/prism_test.zig");
    _ = @import("geometry/segment_test.zig");

    // Math modules
    _ = @import("math/vec2_test.zig");

    // Rendering modules
    _ = @import("rendering/band_test.zig");
    _ = @import("rendering/glow_test.zig");
    _ = @import("rendering/gradient_test.zig");
    _ = @import("rendering/markers_test.zig");
}
