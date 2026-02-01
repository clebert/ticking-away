const std = @import("std");

const lib = @import("lib");
const color_space = lib.color_space;
const frame = lib.frame;
const vignette = lib.effect_vignette;

test "vignette apply" {
    var srgba_colors = [_]color_space.Srgba{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    };

    const band_geometry = frame.Geometry{
        .width = 4,
        .height = 4,
        .y_offset = 0,
        .total_height = 4,
    };
    var band_srgba = frame.BandSrgba{
        .colors = &srgba_colors,
        .geometry = &band_geometry,
    };

    const config = vignette.Config{};
    const geometry = vignette.Geometry{ .center_x = 2, .center_y = 2, .radius = 1.0 };

    vignette.apply(&band_srgba, config, geometry);

    // Corners should be grey (outside circle)
    try std.testing.expect(srgba_colors[0].r < 80); // Grey, not red
    try std.testing.expect(@abs(@as(i16, srgba_colors[0].r) - @as(i16, srgba_colors[0].g)) < 3); // Grey (r ~= g)
}

test "vignette disabled" {
    var srgba_colors = [_]color_space.Srgba{.{ .r = 255, .g = 0, .b = 0, .a = 255 }};

    const band_geometry = frame.Geometry{
        .width = 1,
        .height = 1,
        .y_offset = 0,
        .total_height = 1,
    };
    var band_srgba = frame.BandSrgba{
        .colors = &srgba_colors,
        .geometry = &band_geometry,
    };

    const config = vignette.Config{ .enabled = false };
    const geometry = vignette.Geometry{ .center_x = 0.5, .center_y = 0.5, .radius = 0.1 };

    vignette.apply(&band_srgba, config, geometry);

    // Should be unchanged when disabled
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[0].r);
}
