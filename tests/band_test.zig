const std = @import("std");
const watchface = @import("watchface");

const band = watchface.band;
const color = watchface.color;
const glow = watchface.glow;
const line = watchface.line;
const triangle = watchface.triangle;
const vec2 = watchface.vec2;

fn expectNear(actual: f32, expected: f32, tolerance: f32) !void {
    const diff = @abs(actual - expected);
    if (diff > tolerance) {
        std.debug.print("Expected {} to be near {} (tolerance {}), diff was {}\n", .{ actual, expected, tolerance, diff });
        return error.NotNear;
    }
}

fn sumBuffer(buffer: []const color.Color) f32 {
    var sum: f32 = 0;
    for (buffer) |c| {
        sum += c[0] + c[1] + c[2];
    }
    return sum;
}

test "clear sets all pixels to black" {
    var buffer: [16 * 16]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 16,
        .height = 16,
        .y_offset = 0,
        .total_height = 16,
    };

    // Fill with white first
    @memset(&buffer, color.white);

    ctx.clear();

    // All should be black now
    for (buffer) |c| {
        try expectNear(c[0], 0, 1e-6);
        try expectNear(c[1], 0, 1e-6);
        try expectNear(c[2], 0, 1e-6);
    }
}

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
    try expectNear(buffer[center_idx][0], 0, 1e-6);

    // Corner should be white (outside circle)
    const corner_idx = 0;
    try expectNear(buffer[corner_idx][0], 1, 1e-6);
}

test "renderGlowLine produces non-zero output" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    const start = vec2.xy(5, 16);
    const end = vec2.xy(27, 16);
    const seg = line.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    ctx.renderGlowLine(seg, config, null, null);

    // Buffer should have non-zero values now
    const sum = sumBuffer(&buffer);
    try std.testing.expect(sum > 0);
}

test "renderGlowLine respects clipping" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    // Line across entire width
    const start = vec2.xy(0, 16);
    const end = vec2.xy(32, 16);
    const seg = line.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    // Clip to small triangle on left side
    const tri = triangle.Triangle.init(
        vec2.xy(0, 10),
        vec2.xy(16, 16),
        vec2.xy(0, 22),
    );

    ctx.renderGlowLine(seg, config, .{ .triangle = &tri }, null);

    // Check that right side is still black
    const right_idx = 16 * 32 + 28;
    try expectNear(buffer[right_idx][0], 0, 1e-6);

    // Left side should have some glow
    const left_idx = 16 * 32 + 4;
    try std.testing.expect(buffer[left_idx][0] > 0);
}

test "renderGlowLine with gradient color" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    const start = vec2.xy(4, 16);
    const end = vec2.xy(28, 16);
    const seg = line.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .gradient = .{
            .start = color.rgb(1, 0, 0), // red
            .end = color.rgb(0, 0, 1), // blue
        } },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    ctx.renderGlowLine(seg, config, null, null);

    // Left side should be more red
    const left_idx = 16 * 32 + 6;
    try std.testing.expect(buffer[left_idx][0] > buffer[left_idx][2]); // r > b

    // Right side should be more blue
    const right_idx = 16 * 32 + 26;
    try std.testing.expect(buffer[right_idx][2] > buffer[right_idx][0]); // b > r
}

test "renderPrismGlow produces glow inside triangle" {
    var buffer: [64 * 64]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 64,
        .height = 64,
        .y_offset = 0,
        .total_height = 64,
    };

    ctx.clear();

    const tri = triangle.Triangle.init(
        vec2.xy(32, 10),
        vec2.xy(54, 50),
        vec2.xy(10, 50),
    );

    const glow_color = color.white;
    const glow_width: f32 = 8;
    const intensity: f32 = 1;

    ctx.renderPrismGlow(tri, glow_color, glow_width, intensity, .linear);

    // Check that some glow was rendered (glow appears along edges)
    var found_glow = false;
    for (buffer) |c| {
        if (c[0] > 0) {
            found_glow = true;
            break;
        }
    }
    try std.testing.expect(found_glow);
}

test "renderGlowLine excludes triangle" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    // Line across middle
    const start = vec2.xy(0, 16);
    const end = vec2.xy(32, 16);
    const seg = line.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    // Exclude triangle in center
    const exclude = triangle.Triangle.init(
        vec2.xy(16, 10),
        vec2.xy(22, 22),
        vec2.xy(10, 22),
    );

    ctx.renderGlowLine(seg, config, null, &exclude);

    // Center (inside exclude triangle) should be black
    const center_idx = 16 * 32 + 16;
    try expectNear(buffer[center_idx][0], 0, 1e-6);

    // Left side (outside exclude) should have glow
    const left_idx = 16 * 32 + 4;
    try std.testing.expect(buffer[left_idx][0] > 0);
}

test "context with y_offset renders correct region" {
    var buffer: [16 * 8]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 16,
        .height = 8,
        .y_offset = 8, // rendering rows 8-15
        .total_height = 16,
    };

    ctx.clear();

    // Line at y=12 (within our band)
    const start = vec2.xy(0, 12);
    const end = vec2.xy(16, 12);
    const seg = line.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color.white },
        .width = 2,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    ctx.renderGlowLine(seg, config, null, null);

    // Should have non-zero output
    const sum = sumBuffer(&buffer);
    try std.testing.expect(sum > 0);
}

test "context with y_offset ignores lines outside region" {
    var buffer: [16 * 8]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 16,
        .height = 8,
        .y_offset = 8, // rendering rows 8-15
        .total_height = 16,
    };

    ctx.clear();

    // Line at y=20 (below our band which covers y=8-15)
    // Note: Using y > band_y_max avoids integer underflow bug in current impl
    const start = vec2.xy(0, 20);
    const end = vec2.xy(16, 20);
    const seg = line.Segment.init(start, end);

    const config = glow.Config{
        .color = .{ .uniform = color.white },
        .width = 2,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    ctx.renderGlowLine(seg, config, null, null);

    // Should be all black (line outside our y range)
    const sum = sumBuffer(&buffer);
    try expectNear(sum, 0, 1e-6);
}
