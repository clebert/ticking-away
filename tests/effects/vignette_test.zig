const std = @import("std");
const lib = @import("lib");

const color = lib.color;
const vignette = lib.vignette;

test "vignette apply" {
    var buffer = [_]color.Color{
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
    };

    const config = vignette.Config{};
    const geometry = vignette.Geometry{ .center_x = 2, .center_y = 2, .radius = 1.0 };

    vignette.apply(&buffer, 4, 4, config, geometry);

    // Corners should be grey (outside circle)
    try std.testing.expect(buffer[0][0] < 0.3); // Grey, not red
    try std.testing.expectApproxEqAbs(buffer[0][0], buffer[0][1], 0.01); // Grey (r == g)
}

test "vignette disabled" {
    var buffer = [_]color.Color{color.rgb(1, 0, 0)};

    const config = vignette.Config{ .enabled = false };
    const geometry = vignette.Geometry{ .center_x = 0.5, .center_y = 0.5, .radius = 0.1 };

    vignette.apply(&buffer, 1, 1, config, geometry);

    // Should be unchanged when disabled
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buffer[0][0], 0.001);
}
