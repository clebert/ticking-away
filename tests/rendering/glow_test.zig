const std = @import("std");
const testing = std.testing;
const lib = @import("lib");

const band = lib.band;
const color_space = lib.color_space;
const glow = lib.glow;
const prism = lib.prism;
const segment = lib.segment;
const vec2 = lib.vec2;

fn sumLinearColors(linear_colors: []const color_space.Linear) f32 {
    var sum: f32 = 0;
    for (linear_colors) |c| {
        sum += c.vec[0] + c.vec[1] + c.vec[2];
    }
    return sum;
}

test "renderGlowLine produces non-zero output" {
    var linear_colors: [32 * 32]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    @memset(&linear_colors, color_space.Linear.black);

    const start = vec2.xy(5, 16);
    const end = vec2.xy(27, 16);
    const seg = segment.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color_space.Linear.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    glow.renderLine(&ctx, seg, config, null, null);

    // Buffer should have non-zero values now
    const sum = sumLinearColors(&linear_colors);
    try testing.expect(sum > 0);
}

test "renderGlowLine respects clipping" {
    var linear_colors: [32 * 32]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    @memset(&linear_colors, color_space.Linear.black);

    // Line across entire width
    const start = vec2.xy(0, 16);
    const end = vec2.xy(32, 16);
    const seg = segment.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color_space.Linear.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    // Clip to small triangle on left side
    const tri = prism.Prism.init(vec2.xy(5, 16), 10);

    glow.renderLine(&ctx, seg, config, .{ .prism = &tri }, null);

    // Check that right side is still black
    const right_idx = 16 * 32 + 28;
    try testing.expectApproxEqAbs(linear_colors[right_idx].vec[0], 0, 1e-6);

    // Left side should have some glow
    const left_idx = 16 * 32 + 4;
    try testing.expect(linear_colors[left_idx].vec[0] > 0);
}

test "renderGlowLine with gradient color" {
    var linear_colors: [32 * 32]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    @memset(&linear_colors, color_space.Linear.black);

    const start = vec2.xy(4, 16);
    const end = vec2.xy(28, 16);
    const seg = segment.Segment.init(start, end);

    const config = glow.Config{
        .color = .{
            .gradient = .{
                .start = color_space.Linear.init(1, 0, 0, 1), // red
                .end = color_space.Linear.init(0, 0, 1, 1), // blue
            },
        },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    glow.renderLine(&ctx, seg, config, null, null);

    // Left side should be more red
    const left_idx = 16 * 32 + 6;
    try testing.expect(linear_colors[left_idx].vec[0] > linear_colors[left_idx].vec[2]); // r > b

    // Right side should be more blue
    const right_idx = 16 * 32 + 26;
    try testing.expect(linear_colors[right_idx].vec[2] > linear_colors[right_idx].vec[0]); // b > r
}

test "renderPrismGlow produces glow inside triangle" {
    var linear_colors: [64 * 64]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 64,
        .height = 64,
        .y_offset = 0,
        .total_height = 64,
    };

    @memset(&linear_colors, color_space.Linear.black);

    const tri = prism.Prism.init(vec2.xy(32, 36), 44);

    const glow_color = color_space.Linear.white;
    const glow_width: f32 = 8;
    const intensity: f32 = 1;

    glow.renderPrismEdges(&ctx, tri, glow_color, glow_width, intensity, .linear);

    // Check that some glow was rendered (glow appears along edges)
    var found_glow = false;
    for (linear_colors) |c| {
        if (c.vec[0] > 0) {
            found_glow = true;
            break;
        }
    }
    try testing.expect(found_glow);
}

test "renderGlowLine excludes triangle" {
    var linear_colors: [32 * 32]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    @memset(&linear_colors, color_space.Linear.black);

    // Line across middle
    const start = vec2.xy(0, 16);
    const end = vec2.xy(32, 16);
    const seg = segment.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color_space.Linear.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    // Exclude triangle in center
    const exclude = prism.Prism.init(vec2.xy(16, 18), 12);

    glow.renderLine(&ctx, seg, config, null, &exclude);

    // Center (inside exclude triangle) should be black
    const center_idx = 16 * 32 + 16;
    try testing.expectApproxEqAbs(linear_colors[center_idx].vec[0], 0, 1e-6);

    // Left side (outside exclude) should have glow
    const left_idx = 16 * 32 + 4;
    try testing.expect(linear_colors[left_idx].vec[0] > 0);
}

test "context with y_offset renders correct region" {
    var linear_colors: [16 * 8]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 16,
        .height = 8,
        .y_offset = 8, // rendering rows 8-15
        .total_height = 16,
    };

    @memset(&linear_colors, color_space.Linear.black);

    // Line at y=12 (within our band)
    const start = vec2.xy(0, 12);
    const end = vec2.xy(16, 12);
    const seg = segment.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color_space.Linear.white },
        .width = 2,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    glow.renderLine(&ctx, seg, config, null, null);

    // Should have non-zero output
    const sum = sumLinearColors(&linear_colors);
    try testing.expect(sum > 0);
}

test "context with y_offset ignores lines outside region" {
    var linear_colors: [16 * 8]color_space.Linear = undefined;
    var ctx = band.Context{
        .linear_colors = &linear_colors,
        .width = 16,
        .height = 8,
        .y_offset = 8, // rendering rows 8-15
        .total_height = 16,
    };

    @memset(&linear_colors, color_space.Linear.black);

    // Line at y=20 (below our band which covers y=8-15)
    const start = vec2.xy(0, 20);
    const end = vec2.xy(16, 20);
    const seg = segment.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color_space.Linear.white },
        .width = 2,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    glow.renderLine(&ctx, seg, config, null, null);

    // Should be all black (line outside our y range)
    const sum = sumLinearColors(&linear_colors);
    try testing.expectApproxEqAbs(sum, 0, 1e-6);
}
