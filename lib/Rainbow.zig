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

oklab_colors: [color_count]Oklab,

fn init(srgb_colors: [color_count]Srgb) Self {
    @setEvalBranchQuota(10000);

    var oklab_colors: [color_count]Oklab = undefined;

    for (srgb_colors, 0..) |srgb, i| {
        oklab_colors[i] = srgb.toLinear().toOklab();
    }

    return .{ .oklab_colors = oklab_colors };
}

const oklch_balanced: Self = init(.{
    .{ .r = 255, .g = 64, .b = 64 },
    .{ .r = 255, .g = 160, .b = 0 },
    .{ .r = 220, .g = 220, .b = 0 },
    .{ .r = 0, .g = 200, .b = 80 },
    .{ .r = 0, .g = 180, .b = 220 },
    .{ .r = 80, .g = 100, .b = 255 },
    .{ .r = 180, .g = 80, .b = 255 },
});

const spectral: Self = init(.{
    .{ .r = 255, .g = 0, .b = 0 },
    .{ .r = 255, .g = 127, .b = 0 },
    .{ .r = 255, .g = 255, .b = 0 },
    .{ .r = 0, .g = 255, .b = 0 },
    .{ .r = 0, .g = 127, .b = 255 },
    .{ .r = 0, .g = 0, .b = 255 },
    .{ .r = 139, .g = 0, .b = 255 },
});

pub const PaletteId = enum {
    oklch_balanced,
    spectral,
};

pub fn get(palette_id: PaletteId) Self {
    return switch (palette_id) {
        .oklch_balanced => oklch_balanced,
        .spectral => spectral,
    };
}

pub fn reversed(self: Self) Self {
    var oklab_colors = self.oklab_colors;

    std.mem.reverse(Oklab, &oklab_colors);

    return .{ .oklab_colors = oklab_colors };
}

const edge_fade: Oklab = .{ .vec = .{ 0, 0, 0, 1 } };

/// Colors sit at centers (i + 0.5) / N and interpolate in Oklab; out-of-range
/// positions fade toward edge_fade.
pub fn interpolate(self: Self, normalized_position: f32) Linear {
    std.debug.assert(normalized_position >= 0.0 and normalized_position <= 1.0);

    const color_count_f: f32 = @floatFromInt(color_count);
    const color_position = (normalized_position * color_count_f - 0.5) / (color_count_f - 1.0);
    const clamped_color_position = std.math.clamp(color_position, 0.0, 1.0);

    const scaled_index = clamped_color_position * (color_count_f - 1.0);
    const index: usize = @intFromFloat(@min(@floor(scaled_index), color_count_f - 2.0));
    const fraction = scaled_index - @as(f32, @floatFromInt(index));

    const base = Oklab.lerp(self.oklab_colors[index], self.oklab_colors[index + 1], fraction);

    return Oklab.lerp(base, edge_fade, @abs(color_position - clamped_color_position)).toLinear();
}

/// The solid band colours in palette order, converted to linear light. The sharp
/// ray style fills each equal 1/N slice of [0, 1] with one of these and blends
/// between neighbours only across the one-pixel seam at each band boundary.
pub fn bandColors(self: Self) [color_count]Linear {
    var colors: [color_count]Linear = undefined;

    for (self.oklab_colors, &colors) |oklab, *color| {
        color.* = oklab.toLinear();
    }

    return colors;
}

test "get returns matching rainbow" {
    try std.testing.expectEqual(oklch_balanced.oklab_colors, (get(.oklch_balanced)).oklab_colors);
    try std.testing.expectEqual(spectral.oklab_colors, (get(.spectral)).oklab_colors);
}

test "init converts sRGB through to Oklab" {
    // spectral[0] is pure sRGB red; its Oklab must round-trip to linear (1, 0, 0).
    const red = spectral.oklab_colors[0].toLinear();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[2], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[3], 1e-4);

    const red_linear = (Srgb{ .r = 255, .g = 0, .b = 0 }).toLinear();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red_linear.vec[0], 1e-6);
}

test "init sets alpha to 1" {
    for (oklch_balanced.oklab_colors) |c| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.vec[3], 1e-6);
    }
}

test "reversed swaps first and last colors" {
    const rainbow = spectral;
    const reversed_rainbow = rainbow.reversed();

    try std.testing.expectEqual(rainbow.oklab_colors[0].vec, reversed_rainbow.oklab_colors[6].vec);
    try std.testing.expectEqual(rainbow.oklab_colors[6].vec, reversed_rainbow.oklab_colors[0].vec);
    try std.testing.expectEqual(rainbow.oklab_colors[3].vec, reversed_rainbow.oklab_colors[3].vec);
}

test "interpolate at color center returns that color" {
    const red_center = spectral.interpolate(0.5 / 7.0);
    const violet_center = spectral.interpolate(6.5 / 7.0);

    const expected_red = spectral.oklab_colors[0].toLinear();
    const expected_violet = spectral.oklab_colors[6].toLinear();

    inline for (0..3) |i| {
        try std.testing.expectApproxEqAbs(expected_red.vec[i], red_center.vec[i], 1e-5);
        try std.testing.expectApproxEqAbs(expected_violet.vec[i], violet_center.vec[i], 1e-5);
    }
}

test "bandColors returns each palette colour in linear light" {
    const colors = spectral.bandColors();

    try std.testing.expectEqual(color_count, colors.len);
    try std.testing.expectEqual(spectral.oklab_colors[0].toLinear().vec, colors[0].vec);
    try std.testing.expectEqual(spectral.oklab_colors[3].toLinear().vec, colors[3].vec);
    try std.testing.expectEqual(spectral.oklab_colors[6].toLinear().vec, colors[6].vec);
}

test "interpolate at edges fades toward dark" {
    const at_zero = spectral.interpolate(0.0);
    const at_one = spectral.interpolate(1.0);

    const red = spectral.oklab_colors[0].toLinear();
    const violet = spectral.oklab_colors[6].toLinear();

    try std.testing.expect(at_zero.vec[0] < red.vec[0]);

    try std.testing.expect(at_one.vec[2] < violet.vec[2]);
}
