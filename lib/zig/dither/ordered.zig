const std = @import("std");

const color = @import("../color.zig");
const oklab = @import("../oklab.zig");
const dither = @import("../dither.zig");
const blue_noise = @import("blue_noise.zig");

/// Dither matrix type.
pub const Matrix = enum {
    bayer2x2,
    bayer4x4,
    bayer8x8,
    blue_noise,
};

/// Ordered dithering configuration.
pub const Config = struct {
    matrix: Matrix = .bayer4x4,
    spread: f32 = 0.5,
    chroma_weight: f32 = 2.0,
};

/// 2x2 Bayer matrix (normalized to [-0.5, 0.5]).
const bayer_2x2 = [2][2]f32{
    .{ -0.5, 0.0 },
    .{ 0.25, -0.25 },
};

/// 4x4 Bayer matrix (normalized to [-0.5, 0.5]).
const bayer_4x4 = [4][4]f32{
    .{ -0.5, 0.0, -0.375, 0.125 },
    .{ 0.25, -0.25, 0.375, -0.125 },
    .{ -0.3125, 0.1875, -0.4375, 0.0625 },
    .{ 0.4375, -0.0625, 0.3125, -0.1875 },
};

/// 8x8 Bayer matrix (normalized to [-0.5, 0.5]).
const bayer_8x8 = [8][8]f32{
    .{ -0.5, 0.0, -0.375, 0.125, -0.46875, 0.03125, -0.34375, 0.15625 },
    .{ 0.25, -0.25, 0.375, -0.125, 0.28125, -0.21875, 0.40625, -0.09375 },
    .{ -0.3125, 0.1875, -0.4375, 0.0625, -0.28125, 0.21875, -0.40625, 0.09375 },
    .{ 0.4375, -0.0625, 0.3125, -0.1875, 0.46875, -0.03125, 0.34375, -0.15625 },
    .{ -0.453125, 0.046875, -0.328125, 0.171875, -0.484375, 0.015625, -0.359375, 0.140625 },
    .{ 0.296875, -0.203125, 0.421875, -0.078125, 0.265625, -0.234375, 0.390625, -0.109375 },
    .{ -0.265625, 0.234375, -0.390625, 0.109375, -0.296875, 0.203125, -0.421875, 0.078125 },
    .{ 0.484375, -0.015625, 0.359375, -0.140625, 0.453125, -0.046875, 0.328125, -0.171875 },
};

/// Get threshold value for a pixel coordinate.
pub fn getThreshold(matrix: Matrix, x: usize, y: usize) f32 {
    return switch (matrix) {
        .bayer2x2 => bayer_2x2[y & 1][x & 1],
        .bayer4x4 => bayer_4x4[y & 3][x & 3],
        .bayer8x8 => bayer_8x8[y & 7][x & 7],
        .blue_noise => blk: {
            const val = blue_noise.sample(x, y);
            break :blk @as(f32, @floatFromInt(val)) / 255.0 - 0.5;
        },
    };
}

/// Apply ordered dithering to a linear RGB buffer.
/// Output is written as palette indices to out_indices.
pub fn apply(
    buffer: []const color.Color,
    out_indices: []u8,
    width: usize,
    height: usize,
    config: Config,
    palette: *const dither.PaletteCache,
) void {
    @setFloatMode(.optimized);
    const spread = @min(@max(config.spread, 0.0), 1.0);

    for (0..height) |y| {
        for (0..width) |x| {
            const idx = y * width + x;

            // Convert to OkLab
            var lab = oklab.OkLab.fromLinearRgb(buffer[idx]);

            // Apply threshold to lightness
            const threshold = getThreshold(config.matrix, x, y) * spread;
            lab.l = @min(@max(lab.l + threshold, 0.0), 1.0);

            // Find closest palette color
            out_indices[idx] = @intCast(palette.findClosest(lab, config.chroma_weight));
        }
    }
}

/// Apply ordered dithering and write RGBA output.
pub fn applyRgba(
    buffer: []const color.Color,
    out_rgba: []u8,
    width: usize,
    height: usize,
    config: Config,
    palette: *const dither.PaletteCache,
) void {
    @setFloatMode(.optimized);
    const spread = @min(@max(config.spread, 0.0), 1.0);

    for (0..height) |y| {
        for (0..width) |x| {
            const idx = y * width + x;
            const out_idx = idx * 4;

            // Convert to OkLab
            var lab = oklab.OkLab.fromLinearRgb(buffer[idx]);

            // Apply threshold to lightness
            const threshold = getThreshold(config.matrix, x, y) * spread;
            lab.l = @min(@max(lab.l + threshold, 0.0), 1.0);

            // Find closest palette color
            const pal_idx = palette.findClosest(lab, config.chroma_weight);
            const pal_color = palette.rgb[pal_idx];

            // Write output
            out_rgba[out_idx] = pal_color.r;
            out_rgba[out_idx + 1] = pal_color.g;
            out_rgba[out_idx + 2] = pal_color.b;
            out_rgba[out_idx + 3] = @intFromFloat(@min(@max(buffer[idx][3], 0.0), 1.0) * 255.0);
        }
    }
}

test "bayer threshold range" {
    // All thresholds should be in [-0.5, 0.5]
    for (0..8) |y| {
        for (0..8) |x| {
            const t2 = getThreshold(.bayer2x2, x, y);
            const t4 = getThreshold(.bayer4x4, x, y);
            const t8 = getThreshold(.bayer8x8, x, y);
            const tb = getThreshold(.blue_noise, x, y);

            try std.testing.expect(t2 >= -0.5 and t2 <= 0.5);
            try std.testing.expect(t4 >= -0.5 and t4 <= 0.5);
            try std.testing.expect(t8 >= -0.5 and t8 <= 0.5);
            try std.testing.expect(tb >= -0.5 and tb <= 0.5);
        }
    }
}

test "ordered dithering indices" {
    const palette = dither.PaletteCache.init(&dither.palette_ideal);

    // Create a simple gradient
    var buffer = [_]color.Color{
        color.rgb(0.0, 0.0, 0.0), // Black
        color.rgb(1.0, 1.0, 1.0), // White
        color.rgb(1.0, 0.0, 0.0), // Red
        color.rgb(0.0, 0.0, 1.0), // Blue
    };

    var indices: [4]u8 = undefined;
    const config = Config{ .matrix = .bayer2x2, .spread = 0.5 };

    apply(&buffer, &indices, 2, 2, config, &palette);

    // Black should map to black (index 0)
    try std.testing.expectEqual(@as(u8, 0), indices[0]);
    // White should map to white (index 1)
    try std.testing.expectEqual(@as(u8, 1), indices[1]);
}
