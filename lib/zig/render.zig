const color_space = @import("color_space.zig");
const postprocess = @import("postprocess.zig");
const scanline = @import("scanline.zig");
const watchface = @import("watchface.zig");

pub const OutputConfig = struct {
    dither: ?postprocess.DitherConfig = null,
};

fn applyPostprocessAndOutput(
    linear_colors: []const color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    y_offset: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    // Convert linear to sRGB (via dithering or direct conversion)
    if (output_config.dither) |dither_cfg| {
        if (dither_cfg.mode != .none) {
            if (dither_state) |state| {
                postprocess.applyDither(
                    linear_colors,
                    srgba_colors,
                    width,
                    height,
                    y_offset,
                    dither_cfg,
                    state,
                );
                // Apply effects after conversion (skip vignette when dithering)
                const dither_postprocess = postprocess.Config{
                    .grain = postprocess_config.grain,
                    .grain_geometry = postprocess_config.grain_geometry,
                    .vignette = null,
                    .vignette_geometry = null,
                };
                postprocess.apply(srgba_colors, width, height, dither_postprocess);
                return;
            }
        }
    }

    color_space.Linear.toSrgbaSlice(linear_colors, srgba_colors);

    // Apply effects after conversion
    postprocess.apply(srgba_colors, width, height, postprocess_config);
}

pub fn renderFrame(
    scene: *watchface.Scene,
    linear_colors: []color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    var ctx = scanline.Context{
        .linear_colors = linear_colors,
        .width = width,
        .height = height,
        .y_offset = 0,
        .total_height = height,
    };
    scene.renderBand(&ctx);
    applyPostprocessAndOutput(linear_colors, srgba_colors, width, height, 0, postprocess_config, output_config, dither_state);
}

pub fn renderBand(
    scene: *watchface.Scene,
    linear_colors: []color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    band_height: usize,
    y_offset: usize,
    total_height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    var ctx = scanline.Context{
        .linear_colors = linear_colors,
        .width = width,
        .height = band_height,
        .y_offset = y_offset,
        .total_height = total_height,
    };
    scene.renderBand(&ctx);
    applyPostprocessAndOutput(linear_colors, srgba_colors, width, band_height, y_offset, postprocess_config, output_config, dither_state);
}

pub fn renderBandWithGeometry(
    scene: *watchface.Scene,
    geometry: *const watchface.FrameGeometry,
    linear_colors: []color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    band_height: usize,
    y_offset: usize,
    total_height: usize,
    postprocess_config: postprocess.Config,
    output_config: OutputConfig,
    dither_state: ?*postprocess.DitherState,
) void {
    var ctx = scanline.Context{
        .linear_colors = linear_colors,
        .width = width,
        .height = band_height,
        .y_offset = y_offset,
        .total_height = total_height,
    };
    scene.renderBandWithGeometry(&ctx, geometry);
    applyPostprocessAndOutput(linear_colors, srgba_colors, width, band_height, y_offset, postprocess_config, output_config, dither_state);
}
