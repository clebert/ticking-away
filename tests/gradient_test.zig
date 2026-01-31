const std = @import("std");
const tau = std.math.tau;
const pi = std.math.pi;
const testing = std.testing;
const lib = @import("lib");

const scanline = lib.scanline;
const color_space = lib.color_space;
const gradient = lib.gradient;
const rainbow = lib.rainbow;
const prism = lib.prism;

test "angle normalization edge cases" {
    // Test via the gradient render function behavior
    // We can't directly test normalizeAngle since it's not pub,
    // but we can verify the gradient handles wrap-around correctly
    const p = prism.Prism.init(.{ 50, 50 }, 40);

    var linear_colors: [100 * 100]color_space.Linear = undefined;
    @memset(&linear_colors, color_space.Linear.black);

    var ctx = scanline.Context{
        .linear_colors = &linear_colors,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    const cache = rainbow.getPaletteCache(.saturated);

    // Test with negative-ish angles that need normalization
    gradient.render(
        &ctx,
        .{
            .mode = .external,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = -pi,
            .angle_end = -pi / 2.0,
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        cache,
    );

    // Should have rendered some pixels
    var non_black: usize = 0;
    for (linear_colors) |pixel| {
        if (pixel.vec[0] > 0.001 or pixel.vec[1] > 0.001 or pixel.vec[2] > 0.001) {
            non_black += 1;
        }
    }
    try testing.expect(non_black > 0);
}

test "wrap around gradient at boundary" {
    // Test that a gradient spanning across 0/tau boundary works
    const p = prism.Prism.init(.{ 50, 50 }, 40);

    var linear_colors: [100 * 100]color_space.Linear = undefined;
    @memset(&linear_colors, color_space.Linear.black);

    var ctx = scanline.Context{
        .linear_colors = &linear_colors,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    const cache = rainbow.getPaletteCache(.saturated);

    // Gradient that wraps around: from near-tau to past 0
    gradient.render(
        &ctx,
        .{
            .mode = .external,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = tau - 0.3, // Near end
            .angle_end = 0.3, // Just past start
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        cache,
    );

    // Should have rendered some pixels
    var non_black: usize = 0;
    for (linear_colors) |pixel| {
        if (pixel.vec[0] > 0.001 or pixel.vec[1] > 0.001 or pixel.vec[2] > 0.001) {
            non_black += 1;
        }
    }
    try testing.expect(non_black > 0);
}

test "internal vs external mode" {
    const p = prism.Prism.init(.{ 50, 50 }, 30);
    const cache = rainbow.getPaletteCache(.saturated);

    // External mode buffer
    var ext_linear_colors: [100 * 100]color_space.Linear = undefined;
    @memset(&ext_linear_colors, color_space.Linear.black);

    var ext_ctx = scanline.Context{
        .linear_colors = &ext_linear_colors,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    gradient.render(
        &ext_ctx,
        .{
            .mode = .external,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = 0,
            .angle_end = pi / 2.0,
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        cache,
    );

    // Internal mode buffer
    var int_linear_colors: [100 * 100]color_space.Linear = undefined;
    @memset(&int_linear_colors, color_space.Linear.black);

    var int_ctx = scanline.Context{
        .linear_colors = &int_linear_colors,
        .width = 100,
        .height = 100,
        .y_offset = 0,
        .total_height = 100,
    };

    gradient.render(
        &int_ctx,
        .{
            .mode = .internal,
            .origin_x = 50,
            .origin_y = 50,
            .angle_start = 0,
            .angle_end = pi / 2.0,
            .intensity = 1.0,
            .reverse_spectrum = false,
        },
        .{
            .center_x = 50,
            .center_y = 50,
            .radius = 45,
            .prism = p,
        },
        cache,
    );

    // Center of prism should be colored in internal mode only
    const cent = p.centroid();
    const cx: usize = @intFromFloat(cent[0]);
    const cy: usize = @intFromFloat(cent[1]);
    const center_idx = cy * 100 + cx;

    // External should have black at prism center (inside prism is excluded)
    const ext_center = ext_linear_colors[center_idx];
    const ext_sum = ext_center.vec[0] + ext_center.vec[1] + ext_center.vec[2];

    // External mode excludes prism interior
    try testing.expectApproxEqAbs(ext_sum, 0, 0.01);

    // Internal mode fills prism interior (at least partially in the angle range)
    // The center might not be in the 0 to pi/2 angle range, so we check total pixels instead
    var int_non_black: usize = 0;
    for (int_linear_colors) |pixel| {
        if (pixel.vec[0] > 0.001 or pixel.vec[1] > 0.001 or pixel.vec[2] > 0.001) {
            int_non_black += 1;
        }
    }
    try testing.expect(int_non_black > 0);
}
