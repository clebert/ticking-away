const std = @import("std");
const lib = @import("lib");

const color = lib.color;
const dither = lib.dither;
const error_diffusion = lib.error_diffusion;

test "error buffer init and clear" {
    const allocator = std.testing.allocator;
    var buf = try error_diffusion.ErrorBuffer.init(allocator, 10);
    defer buf.deinit(allocator);

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
    const allocator = std.testing.allocator;
    const palette = dither.PaletteCache.init(&dither.palette_ideal);

    var buffer = [_]color.Color{
        color.rgb(0.0, 0.0, 0.0),
        color.rgb(1.0, 1.0, 1.0),
    };

    var out_rgba: [8]u8 = undefined;
    var err = try error_diffusion.ErrorBuffer.init(allocator, 2);
    defer err.deinit(allocator);

    const config = error_diffusion.Config{ .algorithm = .atkinson };
    error_diffusion.apply(&buffer, &out_rgba, 2, 1, 0, config, &palette, &err);

    // Black should output black
    try std.testing.expectEqual(@as(u8, 0), out_rgba[0]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[1]);
    try std.testing.expectEqual(@as(u8, 0), out_rgba[2]);

    // White should output white
    try std.testing.expectEqual(@as(u8, 255), out_rgba[4]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[5]);
    try std.testing.expectEqual(@as(u8, 255), out_rgba[6]);
}
