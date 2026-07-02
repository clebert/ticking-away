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

pub const oklch_balanced: Self = init(.{
    .{ .r = 255, .g = 64, .b = 64 },
    .{ .r = 255, .g = 160, .b = 0 },
    .{ .r = 220, .g = 220, .b = 0 },
    .{ .r = 0, .g = 200, .b = 80 },
    .{ .r = 0, .g = 180, .b = 220 },
    .{ .r = 80, .g = 100, .b = 255 },
    .{ .r = 180, .g = 80, .b = 255 },
});

pub fn reversed(self: Self) Self {
    var oklab_colors = self.oklab_colors;

    std.mem.reverse(Oklab, &oklab_colors);

    return .{ .oklab_colors = oklab_colors };
}

/// The solid band colours in palette order, converted to linear light. Each equal
/// 1/N slice of [0, 1] is filled with one of these, blending between neighbours only
/// across the one-pixel seam at each band boundary.
pub fn bandColors(self: Self) [color_count]Linear {
    var colors: [color_count]Linear = undefined;

    for (self.oklab_colors, &colors) |oklab, *color| {
        color.* = oklab.toLinear();
    }

    return colors;
}

test "init converts sRGB through to Oklab" {
    // The first palette colour must round-trip its source sRGB through Oklab back to
    // linear light.
    const expected = (Srgb{ .r = 255, .g = 64, .b = 64 }).toLinear();
    const actual = oklch_balanced.oklab_colors[0].toLinear();

    inline for (0..4) |i| {
        try std.testing.expectApproxEqAbs(expected.vec[i], actual.vec[i], 1e-4);
    }
}

test "init sets alpha to 1" {
    for (oklch_balanced.oklab_colors) |c| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.vec[3], 1e-6);
    }
}

test "reversed swaps first and last colors" {
    const rainbow = oklch_balanced;
    const reversed_rainbow = rainbow.reversed();

    try std.testing.expectEqual(rainbow.oklab_colors[0].vec, reversed_rainbow.oklab_colors[6].vec);
    try std.testing.expectEqual(rainbow.oklab_colors[6].vec, reversed_rainbow.oklab_colors[0].vec);
    try std.testing.expectEqual(rainbow.oklab_colors[3].vec, reversed_rainbow.oklab_colors[3].vec);
}

test "bandColors returns each palette colour in linear light" {
    const colors = oklch_balanced.bandColors();

    try std.testing.expectEqual(color_count, colors.len);
    try std.testing.expectEqual(oklch_balanced.oklab_colors[0].toLinear().vec, colors[0].vec);
    try std.testing.expectEqual(oklch_balanced.oklab_colors[3].toLinear().vec, colors[3].vec);
    try std.testing.expectEqual(oklch_balanced.oklab_colors[6].toLinear().vec, colors[6].vec);
}
