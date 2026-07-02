const std = @import("std");

const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

pub const ColorId = enum {
    red,
    orange,
    yellow,
    green,
    blue,
    violet,
};

pub const color_count: usize = @typeInfo(ColorId).@"enum".fields.len;

colors: [color_count]Linear,

fn init(srgb_colors: [color_count]Srgb) Self {
    @setEvalBranchQuota(10000);

    var colors: [color_count]Linear = undefined;

    for (srgb_colors, &colors) |srgb, *color| {
        color.* = srgb.toLinear();
    }

    return .{ .colors = colors };
}

/// The six band colours sampled from the original album cover, in spectral order.
pub const dark_side_of_the_moon: Self = init(.{
    .{ .r = 210, .g = 36, .b = 46 },
    .{ .r = 224, .g = 122, .b = 38 },
    .{ .r = 249, .g = 221, .b = 0 },
    .{ .r = 87, .g = 162, .b = 67 },
    .{ .r = 0, .g = 154, .b = 204 },
    .{ .r = 110, .g = 95, .b = 150 },
});

pub fn reversed(self: Self) Self {
    var colors = self.colors;

    std.mem.reverse(Linear, &colors);

    return .{ .colors = colors };
}

test "init converts sRGB band colours to linear light" {
    const expected = (Srgb{ .r = 210, .g = 36, .b = 46 }).toLinear();

    try std.testing.expectEqual(expected.vec, dark_side_of_the_moon.colors[0].vec);
}

test "reversed mirrors the palette order" {
    const mirrored = dark_side_of_the_moon.reversed();

    for (0..color_count) |i| {
        try std.testing.expectEqual(
            dark_side_of_the_moon.colors[i].vec,
            mirrored.colors[color_count - 1 - i].vec,
        );
    }
}
