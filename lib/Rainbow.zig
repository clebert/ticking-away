const std = @import("std");

const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

colors: [color_count_max]Linear,
len: usize,

pub const Style = enum {
    dark_side_of_the_moon,
    vivid,
    spectrum,
};

/// Upper bound on the band count across every style; sizes the fixed `colors` array.
pub const color_count_max: usize = 7;

/// The six band colours sampled from the original album cover, in spectral order.
pub const dark_side_of_the_moon: Self = init(6, .{
    .{ .r = 210, .g = 36, .b = 46 },
    .{ .r = 224, .g = 122, .b = 38 },
    .{ .r = 249, .g = 221, .b = 0 },
    .{ .r = 87, .g = 162, .b = 67 },
    .{ .r = 0, .g = 154, .b = 204 },
    .{ .r = 110, .g = 95, .b = 150 },
});

/// A vivid seven-band rainbow: every colour sits on the sRGB cube surface.
pub const vivid: Self = init(7, .{
    .{ .r = 255, .g = 64, .b = 64 },
    .{ .r = 255, .g = 160, .b = 0 },
    .{ .r = 220, .g = 220, .b = 0 },
    .{ .r = 0, .g = 200, .b = 80 },
    .{ .r = 0, .g = 180, .b = 220 },
    .{ .r = 80, .g = 100, .b = 255 },
    .{ .r = 180, .g = 80, .b = 255 },
});

/// Bruton's wavelength-to-sRGB at seven spectral hues: 645, 620, 580, 530, 490, 460, 420 nm.
pub const spectrum: Self = init(7, .{
    .{ .r = 255, .g = 0, .b = 0 },
    .{ .r = 255, .g = 119, .b = 0 },
    .{ .r = 255, .g = 255, .b = 0 },
    .{ .r = 94, .g = 255, .b = 0 },
    .{ .r = 0, .g = 255, .b = 255 },
    .{ .r = 0, .g = 123, .b = 255 },
    .{ .r = 106, .g = 0, .b = 255 },
});

fn init(comptime len: usize, srgb_colors: [len]Srgb) Self {
    @setEvalBranchQuota(10000);

    comptime std.debug.assert(len >= 2 and len <= color_count_max);

    var colors = [_]Linear{Linear.black} ** color_count_max;

    for (srgb_colors, colors[0..len]) |srgb, *color| {
        color.* = srgb.toLinear();
    }

    return .{ .colors = colors, .len = len };
}

pub fn get(style: Style) Self {
    return switch (style) {
        .dark_side_of_the_moon => dark_side_of_the_moon,
        .vivid => vivid,
        .spectrum => spectrum,
    };
}

pub fn reversed(self: Self) Self {
    var result = self;

    std.mem.reverse(Linear, result.colors[0..result.len]);

    return result;
}

test "init converts sRGB band colours to linear light" {
    const expected = (Srgb{ .r = 210, .g = 36, .b = 46 }).toLinear();

    try std.testing.expectEqual(expected.vector, dark_side_of_the_moon.colors[0].vector);
}

test "styles carry their own band count" {
    try std.testing.expectEqual(@as(usize, 6), dark_side_of_the_moon.len);
    try std.testing.expectEqual(@as(usize, 7), spectrum.len);
}

test "get returns the palette for a style" {
    try std.testing.expectEqual(spectrum.len, get(.spectrum).len);
    try std.testing.expectEqual(
        dark_side_of_the_moon.colors[0].vector,
        get(.dark_side_of_the_moon).colors[0].vector,
    );
}

test "reversed mirrors the palette order within its length" {
    const mirrored = dark_side_of_the_moon.reversed();

    try std.testing.expectEqual(dark_side_of_the_moon.len, mirrored.len);

    for (0..dark_side_of_the_moon.len) |i| {
        try std.testing.expectEqual(
            dark_side_of_the_moon.colors[i].vector,
            mirrored.colors[dark_side_of_the_moon.len - 1 - i].vector,
        );
    }
}
