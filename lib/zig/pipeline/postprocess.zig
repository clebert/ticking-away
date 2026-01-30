const color = @import("../color/color.zig");
const gamma = @import("../color/gamma.zig");
const dither = @import("../dither/dither.zig");
const error_diffusion = @import("../dither/error_diffusion.zig");
const ordered = @import("../dither/ordered.zig");
const grain = @import("../effects/grain.zig");
const vignette = @import("../effects/vignette.zig");
const boundary = @import("../geometry/boundary.zig");
const output = @import("output.zig");

/// Post-processing configuration.
pub const Config = struct {
    /// Enable gamma correction (linear → sRGB).
    gamma_enabled: bool = true,

    /// Grain effect configuration.
    grain: ?grain.Config = null,

    /// Grain geometry for region masking.
    grain_geometry: ?grain.Geometry = null,

    /// Vignette effect configuration.
    vignette: ?vignette.Config = null,

    /// Vignette geometry (watch circle bounds).
    vignette_geometry: ?vignette.Geometry = null,
};

/// Dither mode selection.
pub const DitherMode = enum {
    none,
    error_diffusion,
    ordered,
};

/// Dithering configuration.
pub const DitherConfig = struct {
    mode: DitherMode = .none,
    palette_type: dither.PaletteType = .ideal,
    error_diffusion: ?error_diffusion.Config = null,
    ordered: ?ordered.Config = null,
    boundary_mask: ?boundary.Boundary = null,
};

/// Dithering state for error diffusion (caller provides storage).
pub const DitherState = struct {
    palette_cache: dither.PaletteCache,
    error_buffer: ?*error_diffusion.ErrorBuffer,

    pub fn init(palette_type: dither.PaletteType) DitherState {
        return .{
            .palette_cache = dither.PaletteCache.init(dither.getPalette(palette_type)),
            .error_buffer = null,
        };
    }

    pub fn setErrorBuffer(self: *DitherState, buf: *error_diffusion.ErrorBuffer) void {
        self.error_buffer = buf;
    }
};

/// Apply post-processing effects to a linear RGB buffer.
/// After this call, buffer is in sRGB space, ready for output.
pub fn apply(
    buffer: []color.Color,
    width: usize,
    height: usize,
    config: Config,
) void {
    // Step 1: Gamma correction (linear → sRGB)
    if (config.gamma_enabled) {
        gamma.applyToBuffer(buffer);
    }

    // Step 2: Grain (in sRGB space)
    if (config.grain) |grain_cfg| {
        grain.apply(buffer, width, height, grain_cfg, config.grain_geometry);
    }

    // Step 3: Vignette (in sRGB space)
    if (config.vignette) |vignette_cfg| {
        if (config.vignette_geometry) |geom| {
            vignette.apply(buffer, width, height, vignette_cfg, geom);
        }
    }
}

/// Apply dithering and write to output buffer.
pub fn applyDither(
    buffer: []const color.Color,
    out_rgba: []u8,
    width: usize,
    height: usize,
    y_offset: usize,
    config: DitherConfig,
    state: *DitherState,
) void {
    switch (config.mode) {
        .none => {
            output.writeRgba(buffer, out_rgba);
        },
        .error_diffusion => {
            if (config.error_diffusion) |ed_cfg| {
                if (state.error_buffer) |err| {
                    error_diffusion.apply(
                        buffer,
                        out_rgba,
                        width,
                        height,
                        y_offset,
                        ed_cfg,
                        &state.palette_cache,
                        err,
                    );
                } else {
                    output.writeRgba(buffer, out_rgba);
                }
            } else {
                output.writeRgba(buffer, out_rgba);
            }
        },
        .ordered => {
            if (config.ordered) |ord_cfg| {
                ordered.applyRgba(
                    buffer,
                    out_rgba,
                    width,
                    height,
                    ord_cfg,
                    &state.palette_cache,
                );
            } else {
                output.writeRgba(buffer, out_rgba);
            }
        },
    }

    // Apply boundary mask if configured
    if (config.boundary_mask) |bnd| {
        const white = state.palette_cache.palette.get(.white);
        applyBoundaryMask(out_rgba, width, height, bnd, white);
    }
}

/// Fill pixels outside the circular boundary with white.
fn applyBoundaryMask(
    out_rgba: []u8,
    width: usize,
    height: usize,
    bnd: boundary.Boundary,
    white: dither.Rgb,
) void {
    const cx = bnd.center[0];
    const cy = bnd.center[1];
    const r_sq = bnd.radius_sq;
    const width_i: i32 = @intCast(width);

    for (0..height) |y| {
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        const dy = py - cy;
        const dy_sq = dy * dy;

        if (dy_sq >= r_sq) {
            // Entire row is outside circle
            fillRowWithWhite(out_rgba, y, 0, width, width, white);
        } else {
            // Calculate x intersection points with circle
            const dx_max = @sqrt(r_sq - dy_sq);
            const x_left: usize = @intCast(@max(0, @as(i32, @intFromFloat(@round(cx - dx_max)))));
            const x_right: usize = @intCast(@min(width_i, @as(i32, @intFromFloat(@round(cx + dx_max)))));

            // Fill regions outside circle on this row
            fillRowWithWhite(out_rgba, y, 0, x_left, width, white);
            fillRowWithWhite(out_rgba, y, x_right, width, width, white);
        }
    }
}

fn fillRowWithWhite(
    out_rgba: []u8,
    y: usize,
    x_start: usize,
    x_end: usize,
    width: usize,
    white: dither.Rgb,
) void {
    for (x_start..x_end) |x| {
        const idx = (y * width + x) * 4;
        out_rgba[idx] = white.r;
        out_rgba[idx + 1] = white.g;
        out_rgba[idx + 2] = white.b;
        out_rgba[idx + 3] = 255;
    }
}
