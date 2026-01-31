const std = @import("std");
const testing = std.testing;

const lib = @import("lib");
const frame = lib.frame;
const color_space = lib.color_space;

test "clearWithBackground creates circle mask" {
    var linear_colors: [32 * 32]color_space.Linear = undefined;
    var srgba_colors: [32 * 32]color_space.Srgba = undefined;
    var band = frame.Band{
        .linear_colors = &linear_colors,
        .srgba_colors = &srgba_colors,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    const cx: f32 = 16;
    const cy: f32 = 16;
    const radius: f32 = 10;

    band.clearWithBackground(cx, cy, radius);

    // Center should be black
    const center_idx = 16 * 32 + 16;
    try testing.expectApproxEqAbs(linear_colors[center_idx].vec[0], 0, 1e-6);

    // Corner should be white (outside circle)
    const corner_idx = 0;
    try testing.expectApproxEqAbs(linear_colors[corner_idx].vec[0], 1, 1e-6);
}
