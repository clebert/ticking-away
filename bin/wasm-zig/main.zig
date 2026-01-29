const watchface = @import("watchface");
const compat = watchface.compat;

// WASM memory management
extern var __heap_base: u8;

export fn getHeapBase() [*]u8 {
    return @ptrCast(&__heap_base);
}

// Static state (cached between frames)
const max_dither_width = 5120;
const dither_buffer_size = max_dither_width * watchface.error_diffusion.ErrorBuffer.rows * watchface.error_diffusion.ErrorBuffer.channels;

var static_scene: watchface.scene.Scene = undefined;
var scene_initialized: bool = false;
var last_width: usize = 0;
var last_height: usize = 0;

var dither_error_backing: [dither_buffer_size]f32 = undefined;
var dither_state: watchface.postprocess.DitherState = undefined;
var dither_state_initialized: bool = false;
var dither_error_buffer: watchface.error_diffusion.ErrorBuffer = undefined;

/// Render the complete watchface using configuration from JS.
export fn renderWatchfaceWithConfig(
    buffer: [*]watchface.color.Color,
    out_rgba: [*]u8,
    width: u32,
    height: u32,
    config_ptr: *compat.WatchfaceConfig,
) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    // Re-initialize scene if dimensions changed
    if (!scene_initialized or w != last_width or h != last_height) {
        static_scene = watchface.scene.Scene.init(w, h);
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
    var dither_state_ptr: ?*watchface.postprocess.DitherState = null;
    if (output_config.dither) |dither_cfg| {
        if (dither_cfg.mode != .none) {
            if (!dither_state_initialized or dither_state.palette_cache.palette != watchface.dither.getPalette(dither_cfg.palette_type)) {
                dither_state = watchface.postprocess.DitherState.init(dither_cfg.palette_type);
                dither_state_initialized = true;
            }

            if (dither_cfg.mode == .error_diffusion and w <= max_dither_width) {
                dither_error_buffer = watchface.error_diffusion.ErrorBuffer.initStatic(&dither_error_backing, w);
                dither_state.setErrorBuffer(&dither_error_buffer);
            }

            dither_state_ptr = &dither_state;
        }
    }

    // Render using pipeline
    watchface.pipeline.renderFrame(
        &static_scene,
        buffer[0 .. w * h],
        out_rgba[0 .. w * h * 4],
        w,
        h,
        postprocess_config,
        output_config,
        dither_state_ptr,
    );
}
