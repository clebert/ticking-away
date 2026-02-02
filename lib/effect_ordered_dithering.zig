const std = @import("std");

const color_space = @import("color_space.zig");
const eink = @import("eink.zig");
const frame = @import("frame.zig");

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

pub fn apply(
    band_linear: *const frame.BandLinear,
    band_srgba: *frame.BandSrgba,
    config: Config,
    palette: *const eink.PaletteCache,
) void {
    const spread = std.math.clamp(config.spread, 0.0, 1.0);
    const band_geometry = band_linear.geometry;

    for (0..band_geometry.height) |local_y| {
        const global_y = band_geometry.globalY(local_y);
        for (0..band_geometry.width) |x| {
            const linear_color = band_linear.colorAt(x, local_y).*;

            var oklab = linear_color.toOklab();

            const threshold = getThreshold(config.matrix, x, global_y) * spread;
            oklab.vec[0] = std.math.clamp(oklab.vec[0] + threshold, 0.0, 1.0);

            const color = palette.findClosest(oklab, config.chroma_weight);
            const srgba_color = palette.getSrgbaColor(color);

            band_srgba.colorAt(x, local_y).* = .{
                .r = srgba_color.r,
                .g = srgba_color.g,
                .b = srgba_color.b,
                .a = @intFromFloat(std.math.clamp(linear_color.vec[3], 0.0, 1.0) * 255.0),
            };
        }
    }
}
