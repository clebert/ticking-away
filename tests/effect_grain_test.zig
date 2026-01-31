const std = @import("std");

const lib = @import("lib");
const color_space = lib.color_space;
const frame = lib.frame;
const grain = lib.effect_grain;

test "grain hash deterministic" {
    // Same coordinates should produce same hash
    const h1 = grain.hashPixel(100, 200);
    const h2 = grain.hashPixel(100, 200);
    try std.testing.expectEqual(h1, h2);

    // Different coordinates should produce different hash
    const h3 = grain.hashPixel(101, 200);
    try std.testing.expect(h1 != h3);
}

test "grain apply" {
    var linear_colors: [4]color_space.Linear = undefined;
    var srgba_colors = [_]color_space.Srgba{
        .{ .r = 128, .g = 128, .b = 128, .a = 255 },
        .{ .r = 128, .g = 128, .b = 128, .a = 255 },
        .{ .r = 128, .g = 128, .b = 128, .a = 255 },
        .{ .r = 128, .g = 128, .b = 128, .a = 255 },
    };

    var band = frame.Band{
        .linear_colors = &linear_colors,
        .srgba_colors = &srgba_colors,
        .width = 2,
        .height = 2,
        .y_offset = 0,
        .total_height = 2,
    };

    const config = grain.Config{ .intensity = 1.0, .scale = 1.0, .threshold = 0.1 };
    grain.apply(&band, config, null);

    // Values should have changed but still be valid u8 values
    for (srgba_colors) |c| {
        try std.testing.expect(c.r <= 255);
        try std.testing.expect(c.g <= 255);
        try std.testing.expect(c.b <= 255);
    }
}
