const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const dither = lib.dither;
const error_diffusion = lib.error_diffusion;

test "error buffer init and clear" {
    const width: usize = 10;
    const size = width * error_diffusion.ErrorBuffer.rows * error_diffusion.ErrorBuffer.channels;
    var backing: [size]f32 = undefined;

    var buf = error_diffusion.ErrorBuffer.init(&backing, width);

    // Should start cleared
    for (buf.data) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }

    // Write some data
    buf.row(0, 0)[0] = 1.0;
    buf.row(1, 1)[5] = 2.0;

    // Clear should reset
    buf.clear();
    for (buf.data) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "error diffusion output" {
    const palette_cache = dither.getPaletteCache(.ideal);

    var linear_colors = [_]color_space.Linear{
        color_space.Linear.init(0.0, 0.0, 0.0, 1.0),
        color_space.Linear.init(1.0, 1.0, 1.0, 1.0),
    };

    var srgba_colors: [8]u8 = undefined;

    const width: usize = 2;
    const size = width * error_diffusion.ErrorBuffer.rows * error_diffusion.ErrorBuffer.channels;
    var backing: [size]f32 = undefined;
    var err = error_diffusion.ErrorBuffer.init(&backing, width);

    const config = error_diffusion.Config{ .algorithm = .atkinson };
    error_diffusion.apply(&linear_colors, &srgba_colors, width, 1, 0, config, palette_cache, &err);

    // Black should output black
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[0]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[1]);
    try std.testing.expectEqual(@as(u8, 0), srgba_colors[2]);

    // White should output white
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[4]);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[5]);
    try std.testing.expectEqual(@as(u8, 255), srgba_colors[6]);
}
