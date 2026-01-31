const std = @import("std");

const color_space = @import("../color/color_space.zig");
const dither = @import("dither.zig");

pub const Matrix = enum {
    bayer2x2,
    bayer4x4,
    bayer8x8,
};

pub const Config = struct {
    matrix: Matrix = .bayer4x4,
    spread: f32 = 0.5,
    chroma_weight: f32 = 2.0,
};

fn bayerValue(comptime N: comptime_int, x: usize, y: usize) f32 {
    const bits = @ctz(@as(usize, N));
    const xor = x ^ y;

    var result: usize = 0;
    for (0..bits) |i| {
        const j = bits - 1 - i;
        const xor_bit = (xor >> @intCast(i)) & 1;
        const y_bit = (y >> @intCast(i)) & 1;
        result |= xor_bit << @intCast(2 * j + 1);
        result |= y_bit << @intCast(2 * j);
    }

    const n_squared: f32 = @floatFromInt(N * N);
    return @as(f32, @floatFromInt(result)) / n_squared - 0.5;
}

fn generateBayerMatrix(comptime N: comptime_int) [N][N]f32 {
    var matrix: [N][N]f32 = undefined;
    for (0..N) |y| {
        for (0..N) |x| {
            matrix[y][x] = bayerValue(N, x, y);
        }
    }
    return matrix;
}

const bayer_2x2 = generateBayerMatrix(2);
const bayer_4x4 = generateBayerMatrix(4);
const bayer_8x8 = generateBayerMatrix(8);

fn getThreshold(matrix: Matrix, x: usize, y: usize) f32 {
    return switch (matrix) {
        .bayer2x2 => bayer_2x2[y & 1][x & 1],
        .bayer4x4 => bayer_4x4[y & 3][x & 3],
        .bayer8x8 => bayer_8x8[y & 7][x & 7],
    };
}

pub fn applyRgba(
    buffer: []const color_space.Linear,
    out_rgba: []u8,
    width: usize,
    height: usize,
    config: Config,
    palette: *const dither.PaletteCache,
) void {
    const spread = std.math.clamp(config.spread, 0.0, 1.0);

    for (0..height) |y| {
        for (0..width) |x| {
            const idx = y * width + x;
            const out_idx = idx * 4;

            var lab = buffer[idx].toOklab();

            const threshold = getThreshold(config.matrix, x, y) * spread;
            lab.vec[0] = std.math.clamp(lab.vec[0] + threshold, 0.0, 1.0);

            const pal_idx = palette.findClosest(lab, config.chroma_weight);
            const pal_color = palette.getRgb(pal_idx);

            out_rgba[out_idx] = pal_color.r;
            out_rgba[out_idx + 1] = pal_color.g;
            out_rgba[out_idx + 2] = pal_color.b;
            out_rgba[out_idx + 3] = @intFromFloat(std.math.clamp(buffer[idx].vec[3], 0.0, 1.0) * 255.0);
        }
    }
}
