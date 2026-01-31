const color_space = @import("../color/color_space.zig");
const eink = @import("../color/eink.zig");
const error_diffusion = @import("../dither/error_diffusion.zig");
const ordered = @import("../dither/ordered.zig");
const grain = @import("../effects/grain.zig");
const vignette = @import("../effects/vignette.zig");
const boundary = @import("../geometry/boundary.zig");

pub const Config = struct {
    grain: ?grain.Config = null,
    grain_geometry: ?grain.Geometry = null,
    vignette: ?vignette.Config = null,
    vignette_geometry: ?vignette.Geometry = null,
};

pub const DitherMode = enum {
    none,
    error_diffusion,
    ordered,
};

pub const DitherConfig = struct {
    mode: DitherMode = .none,
    palette_type: eink.PaletteType = .ideal,
    error_diffusion: ?error_diffusion.Config = null,
    ordered: ?ordered.Config = null,
    boundary_mask: ?boundary.Boundary = null,
};

pub const DitherState = struct {
    palette_cache: *const eink.PaletteCache,
    error_buffer: ?*error_diffusion.ErrorBuffer,

    pub fn init(palette_type: eink.PaletteType) DitherState {
        return .{
            .palette_cache = eink.getPaletteCache(palette_type),
            .error_buffer = null,
        };
    }

    pub fn setErrorBuffer(self: *DitherState, buf: *error_diffusion.ErrorBuffer) void {
        self.error_buffer = buf;
    }
};

pub fn apply(
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    config: Config,
) void {
    if (config.grain) |grain_cfg| {
        grain.apply(srgba_colors, width, height, grain_cfg, config.grain_geometry);
    }

    if (config.vignette) |vignette_cfg| {
        if (config.vignette_geometry) |geom| {
            vignette.apply(srgba_colors, width, height, vignette_cfg, geom);
        }
    }
}

pub fn applyDither(
    linear_colors: []const color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    y_offset: usize,
    config: DitherConfig,
    state: *DitherState,
) void {
    const dithered = switch (config.mode) {
        .none => false,
        .error_diffusion => blk: {
            const ed_cfg = config.error_diffusion orelse break :blk false;
            const err = state.error_buffer orelse break :blk false;
            error_diffusion.apply(linear_colors, srgba_colors, width, height, y_offset, ed_cfg, state.palette_cache, err);
            break :blk true;
        },
        .ordered => blk: {
            const ord_cfg = config.ordered orelse break :blk false;
            ordered.applyRgba(linear_colors, srgba_colors, width, height, ord_cfg, state.palette_cache);
            break :blk true;
        },
    };

    if (!dithered) {
        color_space.Linear.toSrgbaSlice(linear_colors, srgba_colors);
    }

    if (config.boundary_mask) |bnd| {
        const white = state.palette_cache.getSrgbaColor(.white);
        applyBoundaryMask(srgba_colors, width, height, bnd, white);
    }
}

fn applyBoundaryMask(
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    bnd: boundary.Boundary,
    white: color_space.Srgba,
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
            fillRowWithWhite(srgba_colors, y, 0, width, width, white);
        } else {
            const dx_max = @sqrt(r_sq - dy_sq);
            const x_left: usize = @intCast(@max(0, @as(i32, @intFromFloat(@round(cx - dx_max)))));
            const x_right: usize = @intCast(@min(width_i, @as(i32, @intFromFloat(@round(cx + dx_max)))));

            fillRowWithWhite(srgba_colors, y, 0, x_left, width, white);
            fillRowWithWhite(srgba_colors, y, x_right, width, width, white);
        }
    }
}

fn fillRowWithWhite(
    srgba_colors: []color_space.Srgba,
    y: usize,
    x_start: usize,
    x_end: usize,
    width: usize,
    white: color_space.Srgba,
) void {
    for (x_start..x_end) |x| {
        srgba_colors[y * width + x] = .{ .r = white.r, .g = white.g, .b = white.b, .a = 255 };
    }
}
