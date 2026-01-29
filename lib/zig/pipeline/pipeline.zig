const color = @import("../color/color.zig");
const dither = @import("../dither/dither.zig");
const error_diffusion = @import("../dither/error_diffusion.zig");
const ordered = @import("../dither/ordered.zig");
const grain = @import("../effects/grain.zig");
const vignette = @import("../effects/vignette.zig");
const boundary = @import("../geometry/boundary.zig");
const band = @import("../rendering/band.zig");
const Scene = @import("../scene.zig").Scene;
const output = @import("output.zig");
const postprocess = @import("postprocess.zig");

/// Output configuration.
pub const OutputConfig = struct {
    format: output.Format = .rgba8,
    dither: ?postprocess.DitherConfig = null,
};

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
    scene: *Scene,
    float_buffer: []color.Color,
    out_bytes: []u8,
    width: usize,
    height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    // Create band context for full frame
    var ctx = band.Context{
        .buffer = float_buffer,
        .width = width,
        .height = height,
        .y_offset = 0,
        .total_height = height,
    };

    // Render scene geometry (linear RGB)
    scene.renderBand(&ctx);

    // Determine if dithering is enabled
    const dithering_enabled = if (output_config.dither) |d| d.mode != .none else false;

    // Apply post-processing (gamma, grain, vignette)
    // Skip vignette when dithering (it's replaced by boundary masking)
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

    // Output with or without dithering
    if (output_config.dither) |dither_cfg| {
        if (dither_cfg.mode != .none) {
            if (dither_state) |state| {
                postprocess.applyDither(
                    float_buffer,
                    out_bytes,
                    width,
                    height,
                    0,
                    dither_cfg,
                    state,
                );
                return;
            }
        }
    }

    // No dithering - direct output
    output.write(float_buffer, out_bytes, output_config.format);
}

/// Render a single band (for memory-constrained devices).
///
/// Band rendering allows processing one horizontal strip at a time,
/// using only `width × band_height` float buffer instead of full frame.
///
/// For correct error diffusion across bands, the same DitherState must be
/// passed for all bands, and bands must be rendered in order from top to bottom.
pub fn renderBand(
    scene: *Scene,
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

    postprocess.apply(float_buffer, width, band_height, effective_postprocess);

    if (output_config.dither) |dither_cfg| {
        if (dither_cfg.mode != .none) {
            if (dither_state) |state| {
                postprocess.applyDither(
                    float_buffer,
                    out_bytes,
                    width,
                    band_height,
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
