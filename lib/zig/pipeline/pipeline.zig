const color = @import("../color/color.zig");
const band = @import("../rendering/band.zig");
const watchface = @import("../watchface.zig");
const output = @import("output.zig");
const postprocess = @import("postprocess.zig");

/// Output configuration.
pub const OutputConfig = struct {
    format: output.Format = .rgba8,
    dither: ?postprocess.DitherConfig = null,
};

fn applyPostprocessAndOutput(
    float_buffer: []color.Color,
    out_bytes: []u8,
    width: usize,
    height: usize,
    y_offset: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    const dithering_enabled = if (output_config.dither) |d| d.mode != .none else false;

    const effective_postprocess = if (dithering_enabled)
        postprocess.Config{
            .gamma_enabled = postprocess_config.gamma_enabled,
            .grain = postprocess_config.grain,
            .grain_geometry = postprocess_config.grain_geometry,
            .vignette = null,
            .vignette_geometry = null,
        }
    else
        postprocess_config;

    postprocess.apply(float_buffer, width, height, effective_postprocess);

    if (output_config.dither) |dither_cfg| {
        if (dither_cfg.mode != .none) {
            if (dither_state) |state| {
                postprocess.applyDither(
                    float_buffer,
                    out_bytes,
                    width,
                    height,
                    y_offset,
                    dither_cfg,
                    state,
                );
                return;
            }
        }
    }

    output.write(float_buffer, out_bytes, output_config.format);
}

/// Render a complete frame to the output buffer.
///
/// Pipeline stages:
/// 1. Scene.renderBand() → linear RGB
/// 2. Gamma correction → sRGB
/// 3. Grain effect (optional)
/// 4. Vignette effect (optional, skipped when dithering)
/// 5. Dithering or direct output
/// 6. Boundary masking (for dithered output)
pub fn renderFrame(
    scene: *watchface.Scene,
    float_buffer: []color.Color,
    out_bytes: []u8,
    width: usize,
    height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    var ctx = band.Context{
        .buffer = float_buffer,
        .width = width,
        .height = height,
        .y_offset = 0,
        .total_height = height,
    };
    scene.renderBand(&ctx);
    applyPostprocessAndOutput(float_buffer, out_bytes, width, height, 0, postprocess_config, output_config, dither_state);
}

/// Render a single band (for memory-constrained devices).
///
/// Band rendering allows processing one horizontal strip at a time,
/// using only `width × band_height` float buffer instead of full frame.
///
/// For correct error diffusion across bands, the same DitherState must be
/// passed for all bands, and bands must be rendered in order from top to bottom.
pub fn renderBand(
    scene: *watchface.Scene,
    float_buffer: []color.Color,
    out_bytes: []u8,
    width: usize,
    band_height: usize,
    y_offset: usize,
    total_height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    var ctx = band.Context{
        .buffer = float_buffer,
        .width = width,
        .height = band_height,
        .y_offset = y_offset,
        .total_height = total_height,
    };
    scene.renderBand(&ctx);
    applyPostprocessAndOutput(float_buffer, out_bytes, width, band_height, y_offset, postprocess_config, output_config, dither_state);
}

/// Render a single band using pre-computed frame geometry.
///
/// For optimized band rendering, call Scene.prepareFrame() once before the band loop,
/// then pass the geometry to each renderBandWithGeometry() call. This avoids
/// redundant geometry computation (spectrum paths, markers) for each band.
pub fn renderBandWithGeometry(
    scene: *watchface.Scene,
    geometry: *const watchface.FrameGeometry,
    float_buffer: []color.Color,
    out_bytes: []u8,
    width: usize,
    band_height: usize,
    y_offset: usize,
    total_height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    var ctx = band.Context{
        .buffer = float_buffer,
        .width = width,
        .height = band_height,
        .y_offset = y_offset,
        .total_height = total_height,
    };
    scene.renderBandWithGeometry(&ctx, geometry);
    applyPostprocessAndOutput(float_buffer, out_bytes, width, band_height, y_offset, postprocess_config, output_config, dither_state);
}
