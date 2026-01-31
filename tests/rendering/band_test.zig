const std = @import("std");
const testing = std.testing;
const lib = @import("lib");

const band = lib.band;
const color = lib.color;

test "clearWithBackground creates circle mask" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    const cx: f32 = 16;
    const cy: f32 = 16;
    const radius: f32 = 10;

    ctx.clearWithBackground(cx, cy, radius);

    // Center should be black
    const center_idx = 16 * 32 + 16;
    try testing.expectApproxEqAbs(buffer[center_idx][0], 0, 1e-6);

    // Corner should be white (outside circle)
    const corner_idx = 0;
    try testing.expectApproxEqAbs(buffer[corner_idx][0], 1, 1e-6);
}
