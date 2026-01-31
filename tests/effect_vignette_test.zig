const std = @import("std");

const lib = @import("lib");
const color_space = lib.color_space;
const frame = lib.frame;
const vignette = lib.effect_vignette;

test "vignette apply" {
    var linear_colors: [16]color_space.Linear = undefined;
    var srgba_colors = [_]color_space.Srgba{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    };

    var band = frame.Band{
        .linear_colors = &linear_colors,
        .srgba_colors = &srgba_colors,
        .width = 4,
        .height = 4,
        .y_offset = 0,
        .total_height = 4,
    };

    const config = vignette.Config{};
    const geometry = vignette.Geometry{ .center_x = 2, .center_y = 2, .radius = 1.0 };

    vignette.apply(&band, config, geometry);

    // Corners should be grey (outside circle)
    try std.testing.expect(srgba_colors[0].r < 80); // Grey, not red
    try std.testing.expect(@abs(@as(i16, srgba_colors[0].r) - @as(i16, srgba_colors[0].g)) < 3); // Grey (r ~= g)
}

test "vignette disabled" {
    var linear_colors: [1]color_space.Linear = undefined;
    var srgba_colors = [_]color_space.Srgba{.{ .r = 255, .g = 0, .b = 0, .a = 255 }};

    var band = frame.Band{
        .linear_colors = &linear_colors,
        .srgba_colors = &srgba_colors,
        .width = 1,
        .height = 1,
        .y_offset = 0,
        .total_height = 1,
    };

    const config = vignette.Config{ .enabled = false };
    const geometry = vignette.Geometry{ .center_x = 0.5, .center_y = 0.5, .radius = 0.1 };

    vignette.apply(&band, config, geometry);

    // Should be unchanged when disabled
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[0].r);
}
