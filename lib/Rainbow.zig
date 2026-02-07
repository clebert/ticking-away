const std = @import("std");

const Linear = @import("Linear.zig");
const Oklab = @import("Oklab.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

pub const ColorId = enum {
    red,
    orange,
    yellow,
    green,
    cyan,
    blue,
    violet,
};

pub const color_count: usize = @typeInfo(ColorId).@"enum".fields.len;

linear_colors: [color_count]Linear,
oklab_colors: [color_count]Oklab,

fn init(srgb_colors: [color_count]Srgb) Self {
    @setEvalBranchQuota(10000);

    var linear_colors: [color_count]Linear = undefined;
    var oklab_colors: [color_count]Oklab = undefined;

    for (srgb_colors, 0..) |srgb, i| {
        linear_colors[i] = srgb.toLinear();
        oklab_colors[i] = linear_colors[i].toOklab();
    }

    return .{ .linear_colors = linear_colors, .oklab_colors = oklab_colors };
}

/// Perceptually balanced colors tuned in OkLCH
const oklch_balanced: Self = init(.{
    .{ .r = 255, .g = 64, .b = 64 },
    .{ .r = 255, .g = 160, .b = 0 },
    .{ .r = 220, .g = 220, .b = 0 },
    .{ .r = 0, .g = 200, .b = 80 },
    .{ .r = 0, .g = 180, .b = 220 },
    .{ .r = 80, .g = 100, .b = 255 },
    .{ .r = 180, .g = 80, .b = 255 },
});

/// Pure spectral rainbow colors
const spectral: Self = init(.{
    .{ .r = 255, .g = 0, .b = 0 },
    .{ .r = 255, .g = 127, .b = 0 },
    .{ .r = 255, .g = 255, .b = 0 },
    .{ .r = 0, .g = 255, .b = 0 },
    .{ .r = 0, .g = 127, .b = 255 },
    .{ .r = 0, .g = 0, .b = 255 },
    .{ .r = 139, .g = 0, .b = 255 },
});

/// Colors matched to Spectra 6 e-ink display gamut
const spectra6: Self = init(.{
    .{ .r = 178, .g = 19, .b = 24 },
    .{ .r = 220, .g = 130, .b = 35 },
    .{ .r = 240, .g = 220, .b = 60 },
    .{ .r = 70, .g = 145, .b = 55 },
    .{ .r = 0, .g = 140, .b = 200 },
    .{ .r = 30, .g = 70, .b = 160 },
    .{ .r = 100, .g = 30, .b = 160 },
});

pub const PaletteId = enum {
    oklch_balanced,
    spectral,
    spectra6,
};

pub fn get(palette_id: PaletteId) Self {
    return switch (palette_id) {
        .oklch_balanced => oklch_balanced,
        .spectral => spectral,
        .spectra6 => spectra6,
    };
}

pub fn color(self: Self, color_id: ColorId) Linear {
    return self.linear_colors[@intFromEnum(color_id)];
}

pub fn reversed(self: Self) Self {
    var linear_colors = self.linear_colors;
    var oklab_colors = self.oklab_colors;

    std.mem.reverse(Linear, &linear_colors);
    std.mem.reverse(Oklab, &oklab_colors);

    return .{ .linear_colors = linear_colors, .oklab_colors = oklab_colors };
}

const edge_fade: Oklab = .{ .vec = .{ 0, 0, 0, 1 } };

/// Maps normalized_position [0,1] so each color gets an equal-width band.
/// Edge bands fade toward black for wider red and violet.
pub fn interpolate(self: Self, normalized_position: f32) Linear {
    std.debug.assert(normalized_position >= 0.0 and normalized_position <= 1.0);

    const color_count_f: f32 = @floatFromInt(color_count);
    const color_position = (normalized_position * color_count_f - 0.5) / (color_count_f - 1.0);
    const clamped_color_position = std.math.clamp(color_position, 0.0, 1.0);

    const scaled_index = clamped_color_position * @as(f32, color_count - 1);
    const index: usize = @intFromFloat(@min(@floor(scaled_index), color_count - 2));
    const fraction = scaled_index - @as(f32, @floatFromInt(index));

    const base = Oklab.lerp(self.oklab_colors[index], self.oklab_colors[index + 1], fraction);

    return Oklab.lerp(base, edge_fade, @abs(color_position - clamped_color_position)).toLinear();
}

test "get returns matching rainbow" {
    try std.testing.expectEqual(oklch_balanced.linear_colors, (get(.oklch_balanced)).linear_colors);
    try std.testing.expectEqual(spectral.linear_colors, (get(.spectral)).linear_colors);
    try std.testing.expectEqual(spectra6.linear_colors, (get(.spectra6)).linear_colors);
}

test "color returns correct entry by ColorId" {
    const rainbow = oklch_balanced;

    try std.testing.expectEqual(rainbow.linear_colors[0].vec, rainbow.color(.red).vec);
    try std.testing.expectEqual(rainbow.linear_colors[3].vec, rainbow.color(.green).vec);
    try std.testing.expectEqual(rainbow.linear_colors[6].vec, rainbow.color(.violet).vec);
}

test "init converts sRGB to linear" {
    const red = spectral.color(.red);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[3], 1e-6);
}

test "init sets alpha to 1" {
    for (oklch_balanced.linear_colors) |c| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.vec[3], 1e-6);
    }
}

test "reversed swaps first and last colors" {
    const rainbow = spectral;
    const reversed_rainbow = rainbow.reversed();

    try std.testing.expectEqual(rainbow.color(.red).vec, reversed_rainbow.color(.violet).vec);
    try std.testing.expectEqual(rainbow.color(.violet).vec, reversed_rainbow.color(.red).vec);
    try std.testing.expectEqual(rainbow.color(.green).vec, reversed_rainbow.color(.green).vec);
}

test "interpolate at color center returns that color" {
    // Color centers are at (i + 0.5) / color_count
    const red_center = spectral.interpolate(0.5 / 7.0);
    const violet_center = spectral.interpolate(6.5 / 7.0);

    for (0..3) |i| {
        try std.testing.expectApproxEqAbs(spectral.linear_colors[0].vec[i], red_center.vec[i], 1e-5);
        try std.testing.expectApproxEqAbs(spectral.linear_colors[6].vec[i], violet_center.vec[i], 1e-5);
    }
}

test "interpolate at edges fades toward dark" {
    const at_zero = spectral.interpolate(0.0);
    const at_one = spectral.interpolate(1.0);

    // At 0, red shifts toward dark (lower red channel)
    try std.testing.expect(at_zero.vec[0] < spectral.linear_colors[0].vec[0]);

    // At 1, violet shifts toward dark (lower blue channel)
    try std.testing.expect(at_one.vec[2] < spectral.linear_colors[6].vec[2]);
}
