const boundary = @import("boundary.zig");
const color_space = @import("color_space.zig");
const eink = @import("eink.zig");
const error_diffusion = @import("error_diffusion.zig");
const frame = @import("frame.zig");
const ordered = @import("ordered.zig");

pub const Mode = enum {
    error_diffusion,
    ordered,
};

pub const Config = struct {
    mode: Mode = .error_diffusion,
    palette_type: eink.PaletteType = .ideal,
    error_diffusion: ?error_diffusion.Config = null,
    ordered: ?ordered.Config = null,
    boundary_mask: ?boundary.Boundary = null,
};

pub const State = struct {
    palette_cache: *const eink.PaletteCache,
    error_buffer: ?*error_diffusion.ErrorBuffer = null,

    pub fn init(palette_type: eink.PaletteType) State {
        return .{
            .palette_cache = eink.getPaletteCache(palette_type),
        };
    }

    pub fn setErrorBuffer(self: *State, buf: *error_diffusion.ErrorBuffer) void {
        self.error_buffer = buf;
    }
};

pub fn apply(band: *frame.Band, config: Config, state: *State) void {
    const dithered = switch (config.mode) {
        .error_diffusion => blk: {
            const ed_cfg = config.error_diffusion orelse break :blk false;
            const err = state.error_buffer orelse break :blk false;
            error_diffusion.apply(band, ed_cfg, state.palette_cache, err);
            break :blk true;
        },
        .ordered => blk: {
            const ord_cfg = config.ordered orelse break :blk false;
            ordered.apply(band, ord_cfg, state.palette_cache);
            break :blk true;
        },
    };

    if (dithered) {
        if (config.boundary_mask) |bnd| {
            const white = state.palette_cache.getSrgbaColor(.white);
            applyBoundaryMask(band, bnd, white);
        }
    }
}

fn applyBoundaryMask(
    band: *frame.Band,
    bnd: boundary.Boundary,
    white: color_space.Srgba,
) void {
    const cx = bnd.center[0];
    const cy = bnd.center[1];
    const r_sq = bnd.radius_sq;
    const width_i: i32 = @intCast(band.width);

    for (0..band.height) |local_y| {
        const global_y = band.globalY(local_y);
        const py = @as(f32, @floatFromInt(global_y)) + 0.5;
        const dy = py - cy;
        const dy_sq = dy * dy;

        if (dy_sq >= r_sq) {
            fillRowWithWhite(band, local_y, 0, band.width, white);
        } else {
            const dx_max = @sqrt(r_sq - dy_sq);
            const x_left: usize = @intCast(@max(0, @as(i32, @intFromFloat(@round(cx - dx_max)))));
            const x_right: usize = @intCast(@min(width_i, @as(i32, @intFromFloat(@round(cx + dx_max)))));

            fillRowWithWhite(band, local_y, 0, x_left, white);
            fillRowWithWhite(band, local_y, x_right, band.width, white);
        }
    }
}

fn fillRowWithWhite(
    band: *frame.Band,
    local_y: usize,
    x_start: usize,
    x_end: usize,
    white: color_space.Srgba,
) void {
    for (x_start..x_end) |x| {
        band.srgbaColorAt(x, local_y).* = .{ .r = white.r, .g = white.g, .b = white.b, .a = 255 };
    }
}
