const std = @import("std");

const color = @import("color/color.zig");
const oklab = @import("color/oklab.zig");
const dither = @import("dither.zig");

/// Error diffusion algorithm type.
pub const Algorithm = enum {
    atkinson,
    floyd_steinberg,
};

/// Error diffusion configuration.
pub const Config = struct {
    algorithm: Algorithm = .atkinson,
    strength: f32 = 1.0,
    chroma_weight: f32 = 2.0,
    oklab_error: bool = true,
    clear_buffer: bool = true,
};

/// Error buffer for diffusion (3 rows × 3 channels).
pub const ErrorBuffer = struct {
    data: []f32,
    width: usize,

    pub const rows: usize = 3;
    pub const channels: usize = 3;

    pub fn init(allocator: std.mem.Allocator, width: usize) !ErrorBuffer {
        const data = try allocator.alloc(f32, width * rows * channels);
        @memset(data, 0.0);
        return ErrorBuffer{ .data = data, .width = width };
    }

    /// Initialize from a preallocated static buffer.
    pub fn initStatic(backing: []f32, width: usize) ErrorBuffer {
        const needed = width * rows * channels;
        std.debug.assert(backing.len >= needed);
        const data = backing[0..needed];
        @memset(data, 0.0);
        return ErrorBuffer{ .data = data, .width = width };
    }

    pub fn deinit(self: *ErrorBuffer, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    pub fn clear(self: *ErrorBuffer) void {
        @memset(self.data, 0.0);
    }

    pub fn row(self: *ErrorBuffer, r: usize, channel: usize) []f32 {
        const start = r * self.width * channels + channel * self.width;
        return self.data[start .. start + self.width];
    }

    pub fn rotateRows(self: *ErrorBuffer) void {
        const row0_r = self.row(0, 0);
        const row0_g = self.row(0, 1);
        const row0_b = self.row(0, 2);
        const row1_r = self.row(1, 0);
        const row1_g = self.row(1, 1);
        const row1_b = self.row(1, 2);
        const row2_r = self.row(2, 0);
        const row2_g = self.row(2, 1);
        const row2_b = self.row(2, 2);

        for (0..self.width) |i| {
            row0_r[i] = row1_r[i];
            row0_g[i] = row1_g[i];
            row0_b[i] = row1_b[i];
            row1_r[i] = row2_r[i];
            row1_g[i] = row2_g[i];
            row1_b[i] = row2_b[i];
            row2_r[i] = 0.0;
            row2_g[i] = 0.0;
            row2_b[i] = 0.0;
        }
    }
};

inline fn clamp01(x: f32) f32 {
    @setFloatMode(.optimized);
    return @min(@max(x, 0.0), 1.0);
}

/// Apply Atkinson error diffusion.
/// Diffuses 75% of error (1/8 to each of 6 neighbors).
fn applyAtkinson(
    buffer: []const color.Color,
    out_rgba: []u8,
    width: usize,
    height: usize,
    y_offset: usize,
    config: Config,
    palette: *const dither.PaletteCache,
    err: *ErrorBuffer,
) void {
    @setFloatMode(.optimized);
    const d: f32 = 0.125 * config.strength;

    if (config.clear_buffer) {
        err.clear();
    }

    for (0..height) |local_y| {
        // Serpentine scan using global y for consistent direction across bands
        const global_y = local_y + y_offset;
        const left_to_right = (global_y % 2 == 0);

        var x: usize = if (left_to_right) 0 else width - 1;
        while (true) {
            const idx = local_y * width + x;
            const out_idx = idx * 4;

            const px = buffer[idx];
            var pal_idx: usize = undefined;
            var err_1: f32 = undefined;
            var err_2: f32 = undefined;
            var err_3: f32 = undefined;

            if (config.oklab_error) {
                var lab = oklab.OkLab.fromLinearRgb(px);
                lab.l = clamp01(lab.l + err.row(0, 0)[x]);
                lab.a += err.row(0, 1)[x];
                lab.b += err.row(0, 2)[x];

                pal_idx = palette.findClosest(lab, config.chroma_weight);
                const quantized = palette.lab[pal_idx];

                err_1 = (lab.l - quantized.l) * d;
                err_2 = (lab.a - quantized.a) * d;
                err_3 = (lab.b - quantized.b) * d;
            } else {
                const r = clamp01(px[0] + err.row(0, 0)[x]);
                const g = clamp01(px[1] + err.row(0, 1)[x]);
                const b = clamp01(px[2] + err.row(0, 2)[x]);

                const lab = oklab.OkLab.fromLinearRgb(color.rgb(r, g, b));
                pal_idx = palette.findClosest(lab, config.chroma_weight);
                const quantized = palette.linear[pal_idx];

                err_1 = (r - quantized[0]) * d;
                err_2 = (g - quantized[1]) * d;
                err_3 = (b - quantized[2]) * d;
            }

            // Write output
            const pal_color = palette.rgb[pal_idx];
            out_rgba[out_idx] = pal_color.r;
            out_rgba[out_idx + 1] = pal_color.g;
            out_rgba[out_idx + 2] = pal_color.b;
            out_rgba[out_idx + 3] = @intFromFloat(clamp01(px[3]) * 255.0);

            // Diffuse error (Atkinson pattern)
            const x_i: i32 = @intCast(x);
            const width_i: i32 = @intCast(width);
            const step: i32 = if (left_to_right) 1 else -1;
            const fwd1 = x_i + step;
            const fwd2 = x_i + 2 * step;
            const back1 = x_i - step;

            // Current row: fwd1, fwd2
            if (fwd1 >= 0 and fwd1 < width_i) {
                const fx: usize = @intCast(fwd1);
                err.row(0, 0)[fx] += err_1;
                err.row(0, 1)[fx] += err_2;
                err.row(0, 2)[fx] += err_3;
            }
            if (fwd2 >= 0 and fwd2 < width_i) {
                const fx: usize = @intCast(fwd2);
                err.row(0, 0)[fx] += err_1;
                err.row(0, 1)[fx] += err_2;
                err.row(0, 2)[fx] += err_3;
            }
            // Next row: back1, x, fwd1
            if (back1 >= 0 and back1 < width_i) {
                const bx: usize = @intCast(back1);
                err.row(1, 0)[bx] += err_1;
                err.row(1, 1)[bx] += err_2;
                err.row(1, 2)[bx] += err_3;
            }
            err.row(1, 0)[x] += err_1;
            err.row(1, 1)[x] += err_2;
            err.row(1, 2)[x] += err_3;
            if (fwd1 >= 0 and fwd1 < width_i) {
                const fx: usize = @intCast(fwd1);
                err.row(1, 0)[fx] += err_1;
                err.row(1, 1)[fx] += err_2;
                err.row(1, 2)[fx] += err_3;
            }
            // Row +2: x only
            err.row(2, 0)[x] += err_1;
            err.row(2, 1)[x] += err_2;
            err.row(2, 2)[x] += err_3;

            // Advance x
            if (left_to_right) {
                if (x + 1 >= width) break;
                x += 1;
            } else {
                if (x == 0) break;
                x -= 1;
            }
        }

        err.rotateRows();
    }
}

/// Apply Floyd-Steinberg error diffusion.
/// Diffuses 100% of error with weights 7/16, 3/16, 5/16, 1/16.
fn applyFloydSteinberg(
    buffer: []const color.Color,
    out_rgba: []u8,
    width: usize,
    height: usize,
    y_offset: usize,
    config: Config,
    palette: *const dither.PaletteCache,
    err: *ErrorBuffer,
) void {
    @setFloatMode(.optimized);
    const d7: f32 = (7.0 / 16.0) * config.strength;
    const d3: f32 = (3.0 / 16.0) * config.strength;
    const d5: f32 = (5.0 / 16.0) * config.strength;
    const d1: f32 = (1.0 / 16.0) * config.strength;

    if (config.clear_buffer) {
        err.clear();
    }

    for (0..height) |local_y| {
        // Serpentine scan using global y for consistent direction across bands
        const global_y = local_y + y_offset;
        const left_to_right = (global_y % 2 == 0);

        var x: usize = if (left_to_right) 0 else width - 1;
        while (true) {
            const idx = local_y * width + x;
            const out_idx = idx * 4;

            const px = buffer[idx];
            var pal_idx: usize = undefined;
            var err_1: f32 = undefined;
            var err_2: f32 = undefined;
            var err_3: f32 = undefined;

            if (config.oklab_error) {
                var lab = oklab.OkLab.fromLinearRgb(px);
                lab.l = clamp01(lab.l + err.row(0, 0)[x]);
                lab.a += err.row(0, 1)[x];
                lab.b += err.row(0, 2)[x];

                pal_idx = palette.findClosest(lab, config.chroma_weight);
                const quantized = palette.lab[pal_idx];

                err_1 = lab.l - quantized.l;
                err_2 = lab.a - quantized.a;
                err_3 = lab.b - quantized.b;
            } else {
                const r = clamp01(px[0] + err.row(0, 0)[x]);
                const g = clamp01(px[1] + err.row(0, 1)[x]);
                const b = clamp01(px[2] + err.row(0, 2)[x]);

                const lab = oklab.OkLab.fromLinearRgb(color.rgb(r, g, b));
                pal_idx = palette.findClosest(lab, config.chroma_weight);
                const quantized = palette.linear[pal_idx];

                err_1 = r - quantized[0];
                err_2 = g - quantized[1];
                err_3 = b - quantized[2];
            }

            // Write output
            const pal_color = palette.rgb[pal_idx];
            out_rgba[out_idx] = pal_color.r;
            out_rgba[out_idx + 1] = pal_color.g;
            out_rgba[out_idx + 2] = pal_color.b;
            out_rgba[out_idx + 3] = @intFromFloat(clamp01(px[3]) * 255.0);

            // Diffuse error (Floyd-Steinberg pattern)
            const x_i: i32 = @intCast(x);
            const width_i: i32 = @intCast(width);
            const step: i32 = if (left_to_right) 1 else -1;
            const fwd = x_i + step;
            const back = x_i - step;

            // Current row: forward gets 7/16
            if (fwd >= 0 and fwd < width_i) {
                const fx: usize = @intCast(fwd);
                err.row(0, 0)[fx] += err_1 * d7;
                err.row(0, 1)[fx] += err_2 * d7;
                err.row(0, 2)[fx] += err_3 * d7;
            }
            // Next row: back gets 3/16, x gets 5/16, forward gets 1/16
            if (back >= 0 and back < width_i) {
                const bx: usize = @intCast(back);
                err.row(1, 0)[bx] += err_1 * d3;
                err.row(1, 1)[bx] += err_2 * d3;
                err.row(1, 2)[bx] += err_3 * d3;
            }
            err.row(1, 0)[x] += err_1 * d5;
            err.row(1, 1)[x] += err_2 * d5;
            err.row(1, 2)[x] += err_3 * d5;
            if (fwd >= 0 and fwd < width_i) {
                const fx: usize = @intCast(fwd);
                err.row(1, 0)[fx] += err_1 * d1;
                err.row(1, 1)[fx] += err_2 * d1;
                err.row(1, 2)[fx] += err_3 * d1;
            }

            // Advance x
            if (left_to_right) {
                if (x + 1 >= width) break;
                x += 1;
            } else {
                if (x == 0) break;
                x -= 1;
            }
        }

        err.rotateRows();
    }
}

/// Apply error diffusion dithering.
pub fn apply(
    buffer: []const color.Color,
    out_rgba: []u8,
    width: usize,
    height: usize,
    y_offset: usize,
    config: Config,
    palette: *const dither.PaletteCache,
    err: *ErrorBuffer,
) void {
    switch (config.algorithm) {
        .atkinson => applyAtkinson(buffer, out_rgba, width, height, y_offset, config, palette, err),
        .floyd_steinberg => applyFloydSteinberg(buffer, out_rgba, width, height, y_offset, config, palette, err),
    }
}

test "error buffer init and clear" {
    const allocator = std.testing.allocator;
    var buf = try ErrorBuffer.init(allocator, 10);
    defer buf.deinit(allocator);

    // Should start cleared
    for (buf.data) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }

    // Write some data
    buf.row(0, 0)[0] = 1.0;
    buf.row(1, 1)[5] = 2.0;

    // Clear should reset
    buf.clear();
    for (buf.data) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "error diffusion output" {
    const allocator = std.testing.allocator;
    const palette = dither.PaletteCache.init(&dither.palette_ideal);

    var buffer = [_]color.Color{
        color.rgb(0.0, 0.0, 0.0),
        color.rgb(1.0, 1.0, 1.0),
    };

    var out_rgba: [8]u8 = undefined;
    var err = try ErrorBuffer.init(allocator, 2);
    defer err.deinit(allocator);

    const config = Config{ .algorithm = .atkinson };
    apply(&buffer, &out_rgba, 2, 1, 0, config, &palette, &err);

    // Black should output black
    try std.testing.expectEqual(@as(u8, 0), out_rgba[0]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[1]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[2]);

    // White should output white
    try std.testing.expectEqual(@as(u8, 255), out_rgba[4]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[5]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[6]);
}
