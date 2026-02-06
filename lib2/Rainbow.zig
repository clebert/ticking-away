const std = @import("std");

const Linear = @import("Linear.zig");
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

colors: [color_count]Linear,

fn init(srgb_colors: [color_count]Srgb) Self {
    @setEvalBranchQuota(10000);

    var linear_colors: [color_count]Linear = undefined;

    for (srgb_colors, 0..) |srgb, i| {
        linear_colors[i] = srgb.toLinear();
    }

    return .{ .colors = linear_colors };
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
    return self.colors[@intFromEnum(color_id)];
}

pub fn interpolate(self: Self, normalized_position: f32) Linear {
    std.debug.assert(normalized_position >= 0.0 and normalized_position <= 1.0);

    const scaled_index = normalized_position * @as(f32, color_count - 1);
    const index: usize = @intFromFloat(@min(@floor(scaled_index), color_count - 2));
    const fraction = scaled_index - @as(f32, @floatFromInt(index));

    return Linear.lerp(self.colors[index], self.colors[index + 1], fraction);
}

test "get returns matching rainbow" {
    try std.testing.expectEqual(oklch_balanced.colors, (get(.oklch_balanced)).colors);
    try std.testing.expectEqual(spectral.colors, (get(.spectral)).colors);
    try std.testing.expectEqual(spectra6.colors, (get(.spectra6)).colors);
}

test "color returns correct entry by ColorId" {
    const rainbow = oklch_balanced;

    try std.testing.expectEqual(rainbow.colors[0].vec, rainbow.color(.red).vec);
    try std.testing.expectEqual(rainbow.colors[3].vec, rainbow.color(.green).vec);
    try std.testing.expectEqual(rainbow.colors[6].vec, rainbow.color(.violet).vec);
}

test "initFromSrgb converts sRGB to linear" {
    const red = spectral.color(.red);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[3], 1e-6);
}

test "initFromSrgb sets alpha to 1" {
    for (oklch_balanced.colors) |c| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.vec[3], 1e-6);
    }
}

test "interpolate at 0 returns first color" {
    const result = spectral.interpolate(0.0);

    try std.testing.expectEqual(spectral.colors[0].vec, result.vec);
}

test "interpolate at 1 returns last color" {
    const result = spectral.interpolate(1.0);

    try std.testing.expectEqual(spectral.colors[6].vec, result.vec);
}

test "interpolate at midpoint between two colors" {
    const at_orange = spectral.interpolate(1.0 / 6.0);

    try std.testing.expectEqual(spectral.colors[1].vec, at_orange.vec);

    const midpoint = spectral.interpolate(1.0 / 12.0);
    const expected = Linear.lerp(spectral.colors[0], spectral.colors[1], 0.5);

    try std.testing.expectApproxEqAbs(expected.vec[0], midpoint.vec[0], 1e-6);
    try std.testing.expectApproxEqAbs(expected.vec[1], midpoint.vec[1], 1e-6);
    try std.testing.expectApproxEqAbs(expected.vec[2], midpoint.vec[2], 1e-6);
}
