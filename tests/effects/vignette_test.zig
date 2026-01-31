const std = @import("std");
const lib = @import("lib");

const color_space = lib.color_space;
const vignette = lib.vignette;

test "vignette apply" {
    var buffer = [_]color_space.Linear{
        color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1),
        color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1),
        color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1),
        color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1), color_space.Linear.init(1, 0, 0, 1),
    };

    const config = vignette.Config{};
    const geometry = vignette.Geometry{ .center_x = 2, .center_y = 2, .radius = 1.0 };

    vignette.apply(&buffer, 4, 4, config, geometry);

    // Corners should be grey (outside circle)
    try std.testing.expect(buffer[0].vec[0] < 0.3); // Grey, not red
    try std.testing.expectApproxEqAbs(buffer[0].vec[0], buffer[0].vec[1], 0.01); // Grey (r == g)
}

test "vignette disabled" {
    var buffer = [_]color_space.Linear{color_space.Linear.init(1, 0, 0, 1)};

    const config = vignette.Config{ .enabled = false };
    const geometry = vignette.Geometry{ .center_x = 0.5, .center_y = 0.5, .radius = 0.1 };

    vignette.apply(&buffer, 1, 1, config, geometry);

    // Should be unchanged when disabled
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buffer[0].vec[0], 0.001);
}
