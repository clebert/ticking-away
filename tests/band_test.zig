const std = @import("std");

const watchface = @import("watchface");

test "render horizontal glow line" {
    const WIDTH = 100;
    const HEIGHT = 50;

    var buffer: [WIDTH * HEIGHT]watchface.color.Color = undefined;

    var ctx = watchface.band.Context{
        .buffer = &buffer,
        .width = WIDTH,
        .height = HEIGHT,
        .y_offset = 0,
        .total_height = HEIGHT,
    };

    const segment = watchface.line.Segment.init(
        watchface.vec2.xy(0, HEIGHT / 2),
        watchface.vec2.xy(WIDTH, HEIGHT / 2),
    );

    const config = watchface.glow.Config{
        .width = 10,
        .falloff = .quadratic,
        .color = .{ .uniform = watchface.color.rgba(1, 1, 1, 1) },
    };

    ctx.clear();
    ctx.renderGlowLine(segment, config);

    // Center pixel (on the line) should be bright
    const center = buffer[(HEIGHT / 2) * WIDTH + (WIDTH / 2)];
    try std.testing.expect(center[0] > 0.9);

    // Edge pixel (far from line) should be dim
    const edge = buffer[0 * WIDTH + (WIDTH / 2)];
    try std.testing.expect(edge[0] < 0.1);
}

test "glow falloff types" {
    const Falloff = watchface.glow.Falloff;

    // At center (t=0), all falloffs should be 1.0
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.linear.apply(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.quadratic.apply(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.cubic.apply(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), Falloff.exponential.apply(0), 0.001);

    // At edge (t=1), all falloffs should be 0.0
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.linear.apply(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.quadratic.apply(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.cubic.apply(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), Falloff.exponential.apply(1), 0.001);

    // At midpoint (t=0.5): linear=0.5, quadratic=0.25, cubic=0.125
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), Falloff.linear.apply(0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), Falloff.quadratic.apply(0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), Falloff.cubic.apply(0.5), 0.001);
}

test "segment distance calculation" {
    // Horizontal segment from (0, 10) to (100, 10)
    const seg = watchface.line.Segment.init(
        watchface.vec2.xy(0, 10),
        watchface.vec2.xy(100, 10),
    );

    // Point directly above middle of segment
    const result1 = seg.distanceSq(watchface.vec2.xy(50, 15));
    try std.testing.expectApproxEqAbs(@as(f32, 25), result1.distance_sq, 0.001); // 5² = 25
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result1.t, 0.001);

    // Point at segment start
    const result2 = seg.distanceSq(watchface.vec2.xy(0, 10));
    try std.testing.expectApproxEqAbs(@as(f32, 0), result2.distance_sq, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result2.t, 0.001);

    // Point before segment start (should clamp to start)
    const result3 = seg.distanceSq(watchface.vec2.xy(-10, 10));
    try std.testing.expectApproxEqAbs(@as(f32, 100), result3.distance_sq, 0.001); // 10² = 100
    try std.testing.expectApproxEqAbs(@as(f32, 0), result3.t, 0.001);
}

test "degenerate segment (zero length)" {
    // A segment where start == end (single point)
    const point_seg = watchface.line.Segment.init(
        watchface.vec2.xy(10, 10),
        watchface.vec2.xy(10, 10),
    );

    // inv_len_sq should be 0 for degenerate segments
    try std.testing.expectEqual(@as(f32, 0), point_seg.inv_len_sq);

    // Distance from the point should work correctly
    const result1 = point_seg.distanceSq(watchface.vec2.xy(10, 15));
    try std.testing.expectApproxEqAbs(@as(f32, 25), result1.distance_sq, 0.001); // 5² = 25
    try std.testing.expectApproxEqAbs(@as(f32, 0), result1.t, 0.001); // t clamped to 0

    // Distance from the exact point should be 0
    const result2 = point_seg.distanceSq(watchface.vec2.xy(10, 10));
    try std.testing.expectApproxEqAbs(@as(f32, 0), result2.distance_sq, 0.001);

    // Test rendering with degenerate segment doesn't crash
    const WIDTH = 20;
    const HEIGHT = 20;
    var buffer: [WIDTH * HEIGHT]watchface.color.Color = undefined;

    var ctx = watchface.band.Context{
        .buffer = &buffer,
        .width = WIDTH,
        .height = HEIGHT,
        .y_offset = 0,
        .total_height = HEIGHT,
    };

    ctx.clear();
    ctx.renderGlowLine(point_seg, .{
        .width = 5,
        .falloff = .quadratic,
        .color = .{ .uniform = watchface.color.rgba(1, 1, 1, 1) },
    });

    // Pixel at the point location should have some brightness
    const center = buffer[10 * WIDTH + 10];
    try std.testing.expect(center[0] > 0.5);
}
