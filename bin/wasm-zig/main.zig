const std = @import("std");
const allocator = std.heap.wasm_allocator;

const lib = @import("lib");

const compat = @import("compat.zig");

// Allocated buffers (reallocated when dimensions change)
var float_buffer: ?[]lib.color.Color = null;
var rgba_buffer: ?[]u8 = null;
var dither_error_backing: ?[]f32 = null;

// Static state (cached between frames)
var static_scene: lib.watchface.Scene = undefined;
var scene_initialized: bool = false;
var last_width: usize = 0;
var last_height: usize = 0;

var dither_state: lib.postprocess.DitherState = undefined;
var dither_state_initialized: bool = false;
var dither_error_buffer: lib.error_diffusion.ErrorBuffer = undefined;

// Static config buffer for JS to write into
var config_buffer: compat.WatchfaceConfig = undefined;

export fn getConfigBuffer() *compat.WatchfaceConfig {
    return &config_buffer;
}

/// Reallocate buffers if dimensions changed.
fn ensureBuffers(w: usize, h: usize) error{OutOfMemory}!void {
    if (w == last_width and h == last_height and
        float_buffer != null and rgba_buffer != null and dither_error_backing != null)
    {
        return;
    }

    // Free old buffers
    if (float_buffer) |buf| allocator.free(buf);
    if (rgba_buffer) |buf| allocator.free(buf);
    if (dither_error_backing) |buf| allocator.free(buf);

    float_buffer = null;
    rgba_buffer = null;
    dither_error_backing = null;

    // Allocate new buffers with errdefer for cleanup on failure
    const pixel_count = w * h;

    float_buffer = try allocator.alloc(lib.color.Color, pixel_count);
    errdefer {
        allocator.free(float_buffer.?);
        float_buffer = null;
    }

    rgba_buffer = try allocator.alloc(u8, pixel_count * 4);
    errdefer {
        allocator.free(rgba_buffer.?);
        rgba_buffer = null;
    }

    const dither_size =
        w * lib.error_diffusion.ErrorBuffer.rows * lib.error_diffusion.ErrorBuffer.channels;

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

    // Build pipeline configs
    const postprocess_config = compat.toPostprocessConfig(config_ptr, &static_scene);
    const output_config = compat.toOutputConfig(config_ptr, &static_scene);

    // Initialize dither state if needed
    var dither_state_ptr: ?*lib.postprocess.DitherState = null;
    if (output_config.dither) |dither_cfg| {
        if (dither_cfg.mode != .none) {
            if (!dither_state_initialized or dither_state.palette_cache.palette != lib.dither.getPalette(dither_cfg.palette_type)) {
                dither_state = lib.postprocess.DitherState.init(dither_cfg.palette_type);
                dither_state_initialized = true;
            }

            if (dither_cfg.mode == .error_diffusion) {
                dither_error_buffer = lib.error_diffusion.ErrorBuffer.init(dither_error_backing.?, w);
                dither_state.setErrorBuffer(&dither_error_buffer);
            }

            dither_state_ptr = &dither_state;
        }
    }

    // Render using pipeline
    lib.pipeline.renderFrame(
        &static_scene,
        float_buffer.?,
        rgba_buffer.?,
        w,
        h,
        postprocess_config,
        output_config,
        dither_state_ptr,
    );

    return rgba_buffer.?.ptr;
}
