const std = @import("std");
const allocator = std.heap.wasm_allocator;

const lib = @import("lib");

const compat = @import("compat.zig");

// Allocated buffers (reallocated when dimensions change)
var linear_colors: ?[]lib.color_space.Linear = null;
var srgba_colors: ?[]lib.color_space.Srgba = null;
var dither_error_backing: ?[]f32 = null;

// Static state (cached between frames)
var static_scene: lib.watchface.Scene = undefined;
var scene_initialized: bool = false;
var last_width: usize = 0;
var last_height: usize = 0;

// Static config buffer for JS to write into
var config_buffer: compat.WatchfaceConfig = undefined;

export fn getConfigBuffer() *compat.WatchfaceConfig {
    return &config_buffer;
}

/// Reallocate buffers if dimensions changed.
fn ensureBuffers(w: usize, h: usize) error{OutOfMemory}!void {
    if (w == last_width and h == last_height and
        linear_colors != null and srgba_colors != null and dither_error_backing != null)
    {
        return;
    }

    // Free old buffers
    if (linear_colors) |buf| allocator.free(buf);
    if (srgba_colors) |buf| allocator.free(buf);
    if (dither_error_backing) |buf| allocator.free(buf);

    linear_colors = null;
    srgba_colors = null;
    dither_error_backing = null;

    // Allocate new buffers with errdefer for cleanup on failure
    const pixel_count = w * h;

    linear_colors = try allocator.alloc(lib.color_space.Linear, pixel_count);
    errdefer {
        allocator.free(linear_colors.?);
        linear_colors = null;
    }

    srgba_colors = try allocator.alloc(lib.color_space.Srgba, pixel_count);
    errdefer {
        allocator.free(srgba_colors.?);
        srgba_colors = null;
    }

    const dither_size =
        w * lib.effect_error_diffusion.ErrorBuffer.rows * lib.effect_error_diffusion.ErrorBuffer.channels;

    dither_error_backing = try allocator.alloc(f32, dither_size);
}

/// Render the complete watchface using configuration from JS.
/// Returns pointer to RGBA buffer, or null on allocation failure.
export fn renderWatchfaceWithConfig(
    width: u32,
    height: u32,
    config_ptr: *compat.WatchfaceConfig,
) ?[*]u8 {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    // Ensure buffers are allocated for current dimensions
    ensureBuffers(w, h) catch return null;

    // Re-initialize scene if dimensions changed
    if (!scene_initialized or w != last_width or h != last_height) {
        static_scene = lib.watchface.Scene.init(w, h);
        scene_initialized = true;
        last_width = w;
        last_height = h;
    }

    // Apply scene configuration
    const scene_config = compat.toSceneConfig(config_ptr);
    static_scene.setPrismConfig(scene_config.prism);
    static_scene.setGlowConfig(scene_config.glow_config);
    static_scene.setRayConfig(scene_config.ray);
    static_scene.setMarkerConfig(scene_config.marker);
    static_scene.setTime(config_ptr.hour, config_ptr.minute);

    // Render scene
    var geometry = lib.frame.Geometry{
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };
    var band_linear = lib.frame.BandLinear{
        .colors = linear_colors.?,
        .geometry = &geometry,
    };

    static_scene.render(&band_linear);

    // Apply dither effect or convert to sRGB
    if (config_ptr.dither.enabled != 0) {
        const palette_type = compat.toDitherPaletteType(config_ptr.dither.mode);
        const palette = lib.eink.getPaletteCache(palette_type);

        var band_srgba = lib.frame.BandSrgba{
            .colors = srgba_colors.?,
            .geometry = &geometry,
        };

        switch (config_ptr.dither.dither_type) {
            .error_diffusion => {
                var err = lib.effect_error_diffusion.ErrorBuffer.init(dither_error_backing.?, w);
                lib.effect_error_diffusion.apply(&band_linear, &band_srgba, compat.toErrorDiffusionConfig(&config_ptr.dither), palette, &err);
            },
            .ordered => {
                lib.effect_ordered_dithering.apply(&band_linear, &band_srgba, compat.toOrderedDitherConfig(&config_ptr.dither), palette);
            },
        }

        const bnd = lib.boundary.Boundary.init(static_scene.center, static_scene.radius);
        lib.effect_boundary_mask.apply(&band_srgba, bnd, palette.getSrgbaColor(.white));
    } else {
        var band_srgba = band_linear.toSrgba(srgba_colors.?);

        lib.effect_grain.apply(
            &band_srgba,
            compat.toGrainConfig(&config_ptr.grain),
            compat.toGrainGeometry(&static_scene),
        );

        lib.effect_vignette.apply(
            &band_srgba,
            compat.toVignetteConfig(&config_ptr.vignette),
            compat.toVignetteGeometry(&static_scene),
        );
    }

    return @ptrCast(srgba_colors.?.ptr);
}
