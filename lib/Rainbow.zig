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

pub fn reversed(self: Self) Self {
    var oklab_colors = self.oklab_colors;

    std.mem.reverse(Oklab, &oklab_colors);

    return .{ .oklab_colors = oklab_colors };
}

const edge_fade: Oklab = .{ .vec = .{ 0, 0, 0, 1 } };

/// Places each palette color at its center (i + 0.5) / N and interpolates between
/// adjacent centers in Oklab. Edge bands fade toward black for wider red and violet.
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

test "get returns matching rainbow" {
    try std.testing.expectEqual(oklch_balanced.oklab_colors, (get(.oklch_balanced)).oklab_colors);
    try std.testing.expectEqual(spectral.oklab_colors, (get(.spectral)).oklab_colors);
    try std.testing.expectEqual(spectra6.oklab_colors, (get(.spectra6)).oklab_colors);
}

test "init converts sRGB through to Oklab" {
    // spectral red is pure sRGB red; round-tripping its stored Oklab back to
    // linear should recover (1, 0, 0).
    const red = spectral.oklab_colors[0].toLinear();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), red.vec[2], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), red.vec[3], 1e-4);

    // Direct sRGB -> linear check, independent of the Oklab round-trip above.
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
    // Color centers are at (i + 0.5) / color_count
    const red_center = spectral.interpolate(0.5 / 7.0);
    const violet_center = spectral.interpolate(6.5 / 7.0);

    const expected_red = spectral.oklab_colors[0].toLinear();
    const expected_violet = spectral.oklab_colors[6].toLinear();

    inline for (0..3) |i| {
        try std.testing.expectApproxEqAbs(expected_red.vec[i], red_center.vec[i], 1e-5);
        try std.testing.expectApproxEqAbs(expected_violet.vec[i], violet_center.vec[i], 1e-5);
    }
}

test "interpolate at edges fades toward dark" {
    const at_zero = spectral.interpolate(0.0);
    const at_one = spectral.interpolate(1.0);

    const red = spectral.oklab_colors[0].toLinear();
    const violet = spectral.oklab_colors[6].toLinear();

    // At 0, red shifts toward dark (lower red channel)
    try std.testing.expect(at_zero.vec[0] < red.vec[0]);

    // At 1, violet shifts toward dark (lower blue channel)
    try std.testing.expect(at_one.vec[2] < violet.vec[2]);
}
