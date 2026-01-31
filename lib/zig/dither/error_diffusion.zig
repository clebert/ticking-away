const std = @import("std");

const color_space = @import("../color/color_space.zig");
const dither = @import("../color/dither.zig");

const Algorithm = enum {
    atkinson,
    floyd_steinberg,
};

pub const Config = struct {
    algorithm: Algorithm = .atkinson,
    strength: f32 = 1.0,
    chroma_weight: f32 = 2.0,
    oklab_error: bool = true,
    clear_buffer: bool = true,
};

const QuantResult = struct {
    color: dither.Color,
    error_1: f32,
    error_2: f32,
    error_3: f32,
};

pub const ErrorBuffer = struct {
    data: []f32,
    width: usize,

    pub const rows: usize = 3;
    pub const channels: usize = 3;

    pub fn init(backing: []f32, width: usize) ErrorBuffer {
        const needed = width * rows * channels;
        std.debug.assert(backing.len >= needed);
        const data = backing[0..needed];
        @memset(data, 0.0);
        return .{ .data = data, .width = width };
    }

    pub fn clear(self: *ErrorBuffer) void {
        @memset(self.data, 0.0);
    }

    pub fn row(self: *ErrorBuffer, r: usize, channel: usize) []f32 {
        const start = r * self.width * channels + channel * self.width;
        return self.data[start .. start + self.width];
    }

    pub fn rotateRows(self: *ErrorBuffer) void {
        const row_size = self.width * channels;
        const row0 = self.data[0..row_size];
        const row1 = self.data[row_size .. 2 * row_size];
        const row2 = self.data[2 * row_size .. 3 * row_size];
        @memcpy(row0, row1);
        @memcpy(row1, row2);
        @memset(row2, 0.0);
    }
};

pub fn apply(
    linear_colors: []const color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    y_offset: usize,
    config: Config,
    palette: *const dither.PaletteCache,
    err: *ErrorBuffer,
) void {
    if (config.clear_buffer) {
        err.clear();
    }

    for (0..height) |local_y| {
        const global_y = local_y + y_offset;
        const left_to_right = (global_y % 2 == 0);

        for (0..width) |i| {
            const x = if (left_to_right) i else width - 1 - i;
            const idx = local_y * width + x;

            const pixel = linear_colors[idx];
            const quant: QuantResult = if (config.oklab_error) blk: {
                var oklab = pixel.toOklab();
                oklab.vec[0] = std.math.clamp(oklab.vec[0] + err.row(0, 0)[x], 0.0, 1.0);
                oklab.vec[1] += err.row(0, 1)[x];
                oklab.vec[2] += err.row(0, 2)[x];

                const color_found = palette.findClosest(oklab, config.chroma_weight);
                const quantized = palette.oklab_colors[@intFromEnum(color_found)];

                break :blk .{
                    .color = color_found,
                    .error_1 = oklab.vec[0] - quantized.vec[0],
                    .error_2 = oklab.vec[1] - quantized.vec[1],
                    .error_3 = oklab.vec[2] - quantized.vec[2],
                };
            } else blk: {
                const r = std.math.clamp(pixel.vec[0] + err.row(0, 0)[x], 0.0, 1.0);
                const g = std.math.clamp(pixel.vec[1] + err.row(0, 1)[x], 0.0, 1.0);
                const b = std.math.clamp(pixel.vec[2] + err.row(0, 2)[x], 0.0, 1.0);

                const oklab = color_space.Linear.init(r, g, b, pixel.vec[3]).toOklab();
                const color_found = palette.findClosest(oklab, config.chroma_weight);
                const quantized = palette.linear_colors[@intFromEnum(color_found)];

                break :blk .{
                    .color = color_found,
                    .error_1 = r - quantized.vec[0],
                    .error_2 = g - quantized.vec[1],
                    .error_3 = b - quantized.vec[2],
                };
            };

            const srgba_color = palette.getSrgbaColor(quant.color);
            srgba_colors[idx] = .{
                .r = srgba_color.r,
                .g = srgba_color.g,
                .b = srgba_color.b,
                .a = @intFromFloat(std.math.clamp(pixel.vec[3], 0.0, 1.0) * 255.0),
            };

            const x_i: i32 = @intCast(x);
            const width_i: i32 = @intCast(width);
            const step: i32 = if (left_to_right) 1 else -1;
            const fwd = x_i + step;
            const back = x_i - step;

            switch (config.algorithm) {
                .atkinson => {
                    const d: f32 = 0.125 * config.strength;
                    const e1 = quant.error_1 * d;
                    const e2 = quant.error_2 * d;
                    const e3 = quant.error_3 * d;
                    const fwd2 = x_i + 2 * step;

                    if (fwd >= 0 and fwd < width_i) {
                        const fx: usize = @intCast(fwd);
                        err.row(0, 0)[fx] += e1;
                        err.row(0, 1)[fx] += e2;
                        err.row(0, 2)[fx] += e3;
                        err.row(1, 0)[fx] += e1;
                        err.row(1, 1)[fx] += e2;
                        err.row(1, 2)[fx] += e3;
                    }
                    if (fwd2 >= 0 and fwd2 < width_i) {
                        const fx: usize = @intCast(fwd2);
                        err.row(0, 0)[fx] += e1;
                        err.row(0, 1)[fx] += e2;
                        err.row(0, 2)[fx] += e3;
                    }
                    if (back >= 0 and back < width_i) {
                        const bx: usize = @intCast(back);
                        err.row(1, 0)[bx] += e1;
                        err.row(1, 1)[bx] += e2;
                        err.row(1, 2)[bx] += e3;
                    }
                    err.row(1, 0)[x] += e1;
                    err.row(1, 1)[x] += e2;
                    err.row(1, 2)[x] += e3;
                    err.row(2, 0)[x] += e1;
                    err.row(2, 1)[x] += e2;
                    err.row(2, 2)[x] += e3;
                },
                .floyd_steinberg => {
                    const s = config.strength;
                    if (fwd >= 0 and fwd < width_i) {
                        const fx: usize = @intCast(fwd);
                        const d7: f32 = (7.0 / 16.0) * s;
                        err.row(0, 0)[fx] += quant.error_1 * d7;
                        err.row(0, 1)[fx] += quant.error_2 * d7;
                        err.row(0, 2)[fx] += quant.error_3 * d7;
                    }
                    if (back >= 0 and back < width_i) {
                        const bx: usize = @intCast(back);
                        const d3: f32 = (3.0 / 16.0) * s;
                        err.row(1, 0)[bx] += quant.error_1 * d3;
                        err.row(1, 1)[bx] += quant.error_2 * d3;
                        err.row(1, 2)[bx] += quant.error_3 * d3;
                    }
                    const d5: f32 = (5.0 / 16.0) * s;
                    err.row(1, 0)[x] += quant.error_1 * d5;
                    err.row(1, 1)[x] += quant.error_2 * d5;
                    err.row(1, 2)[x] += quant.error_3 * d5;
                    if (fwd >= 0 and fwd < width_i) {
                        const fx: usize = @intCast(fwd);
                        const d1: f32 = (1.0 / 16.0) * s;
                        err.row(1, 0)[fx] += quant.error_1 * d1;
                        err.row(1, 1)[fx] += quant.error_2 * d1;
                        err.row(1, 2)[fx] += quant.error_3 * d1;
                    }
                },
            }
        }

        err.rotateRows();
    }
}
