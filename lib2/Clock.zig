const std = @import("std");

const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Ray = @import("Ray.zig");
const Scene = @import("Scene.zig");
const Segment = @import("Segment.zig");
const Time = @import("Time.zig");
const vector = @import("vector.zig");

const Self = @This();

const hour_arc: f32 = std.math.pi / 6.0; // 2π/12 = π/6 ≈ 30° (one hour moves 30°)
const apex_angle: f32 = -std.math.pi / 2.0; // −π/2 (−90°, 12 o'clock)
const max_rainbow_spread_radians: f32 = std.math.pi / 6.0;

external_minute_hand: Segment,
internal_minute_hand: ?Segment,
internal_hour_hand: std.EnumArray(Rainbow.ColorId, Segment),
external_hour_hand: std.EnumArray(Rainbow.ColorId, Segment),

pub fn init(time: Time, scene: Scene) ?Self {
    std.debug.assert(scene.radius > 0.0 and scene.radius <= 1.0);

    std.debug.assert(
        scene.normalized_rainbow_spread >= 0.0 and scene.normalized_rainbow_spread <= 1.0,
    );

    const hour_count: usize = @intFromFloat(time.minutes / 60.0);
    const hour: u4 = @intCast(@mod(hour_count, 12));
    const minute = time.minutes - @as(f32, @floatFromInt(hour_count)) * 60.0;
    const minute_angle = apex_angle + (minute / 60.0) * std.math.tau;

    const minute_position = @as(@Vector(2, f32), .{ @cos(minute_angle), @sin(minute_angle) }) *
        @as(@Vector(2, f32), @splat(scene.radius));

    const minute_ray = Ray.init(minute_position, .{ 0, 0 });
    const minute_prism_intersection = scene.prism.intersect(minute_ray) orelse return null;

    const external_minute_hand: Segment = .{
        .start = minute_position,
        .end = minute_prism_intersection.hit,
    };

    const internal_minute_hand: ?Segment = if (bouncingVertex(hour, minute)) |vertex_id| blk: {
        break :blk .{ .start = external_minute_hand.end, .end = scene.prism.vertices.get(vertex_id) };
    } else null;

    const internal_hour_hand_start =
        if (internal_minute_hand) |hand| hand.end else external_minute_hand.end;

    const hour_angle = apex_angle + (@as(f32, @floatFromInt(hour)) / 12.0) *
        std.math.tau + (minute / 60.0) * hour_arc;

    const spread_radians = scene.normalized_rainbow_spread * max_rainbow_spread_radians;

    var internal_hour_hand: std.EnumArray(Rainbow.ColorId, Segment) = undefined;
    var external_hour_hand: std.EnumArray(Rainbow.ColorId, Segment) = undefined;

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const color_index: f32 = @floatFromInt(@intFromEnum(color_id));

        const normalized_position =
            (color_index + 0.5) / @as(f32, @floatFromInt(Rainbow.color_count));

        const color_angle = hour_angle + (0.5 - normalized_position) * spread_radians;

        const hour_ray = Ray.init(.{ 0, 0 }, .{ @cos(color_angle), @sin(color_angle) });
        const hour_prism_intersection = scene.prism.intersect(hour_ray) orelse return null;
        const hour_boundary_intersection = hour_ray.intersectCircle(scene.radius) orelse return null;

        internal_hour_hand.set(color_id, .{
            .start = internal_hour_hand_start,
            .end = hour_prism_intersection.hit,
        });

        external_hour_hand.set(color_id, .{
            .start = hour_prism_intersection.hit,
            .end = hour_boundary_intersection.hit,
        });
    }

    return .{
        .external_minute_hand = external_minute_hand,
        .internal_minute_hand = internal_minute_hand,
        .internal_hour_hand = internal_hour_hand,
        .external_hour_hand = external_hour_hand,
    };
}

fn bouncingVertex(hour: u4, minute: f32) ?Prism.VertexId {
    switch (hour) {
        0, 1, 2 => if (minute < 25.0 or minute > 55.0) return .bottom_left,
        3 => if (minute < 25.0) return .bottom_left,
        4, 5, 6, 7 => if (minute > 15.0 and minute < 45.0) return .apex,
        8 => if (minute > 35.0) return .bottom_right,
        9, 10, 11 => if (minute < 5.0 or minute > 35.0) return .bottom_right,
        else => unreachable,
    }

    return null;
}

const test_scene = Scene{
    .radius = 1.0,
    .prism = Prism.init(0.8),
    .normalized_rainbow_spread = 0.5,
};

fn expectInitNonNull(minutes: f32) Self {
    return Self.init(.{ .minutes = minutes }, test_scene) orelse {
        std.debug.panic("expected non-null Clock for minutes={d:.1}", .{minutes});
    };
}

test "init returns non-null at 12:00" {
    _ = expectInitNonNull(0.0);
}

test "init returns non-null at 3:15" {
    _ = expectInitNonNull(195.0);
}

test "init minute hand starts on circle boundary" {
    const watchface = expectInitNonNull(0.0);
    const start_distance = vector.length(watchface.external_minute_hand.start);

    try std.testing.expectApproxEqAbs(test_scene.radius, start_distance, vector.tolerance);
}

test "init minute hand ends on prism edge" {
    const watchface = expectInitNonNull(0.0);
    const end = watchface.external_minute_hand.end;
    const ray = Ray.init(watchface.external_minute_hand.start, end);
    const intersection = test_scene.prism.intersect(ray).?;

    try std.testing.expectApproxEqAbs(intersection.hit[0], end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(intersection.hit[1], end[1], vector.tolerance);
}

test "init internal_minute_hand is non-null when bouncing" {
    // hour=0, minute=10 → bouncingVertex returns .bottom_left
    const watchface = expectInitNonNull(10.0);

    try std.testing.expect(watchface.internal_minute_hand != null);
}

test "init internal_minute_hand is null when not bouncing" {
    // hour=0, minute=30 → bouncingVertex returns null
    const watchface = expectInitNonNull(30.0);

    try std.testing.expectEqual(null, watchface.internal_minute_hand);
}

test "init internal_minute_hand ends at prism vertex when bouncing" {
    // hour=0, minute=10 → bounces to .bottom_left
    const watchface = expectInitNonNull(10.0);
    const hand = watchface.internal_minute_hand.?;
    const expected = test_scene.prism.vertices.get(.bottom_left);

    try std.testing.expectApproxEqAbs(expected[0], hand.end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(expected[1], hand.end[1], vector.tolerance);
}

test "init all hour hand colors share same internal start" {
    const watchface = expectInitNonNull(0.0);
    const first = watchface.internal_hour_hand.get(.red).start;

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const start = watchface.internal_hour_hand.get(color_id).start;

        try std.testing.expectApproxEqAbs(first[0], start[0], vector.tolerance);
        try std.testing.expectApproxEqAbs(first[1], start[1], vector.tolerance);
    }
}

test "init external hour hand endpoints lie on circle boundary" {
    const watchface = expectInitNonNull(195.0);

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const end = watchface.external_hour_hand.get(color_id).end;
        const distance = vector.length(end);

        try std.testing.expectApproxEqAbs(test_scene.radius, distance, vector.tolerance);
    }
}

test "init internal hour hand start matches minute hand chain" {
    // When bouncing: internal_hour_hand start == internal_minute_hand end
    const watchface_bouncing = expectInitNonNull(10.0);
    const bounce_hand = watchface_bouncing.internal_minute_hand.?;
    const hour_start = watchface_bouncing.internal_hour_hand.get(.red).start;

    try std.testing.expectApproxEqAbs(bounce_hand.end[0], hour_start[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(bounce_hand.end[1], hour_start[1], vector.tolerance);

    // When not bouncing: internal_hour_hand start == external_minute_hand end
    const watchface_direct = expectInitNonNull(30.0);
    const minute_end = watchface_direct.external_minute_hand.end;
    const hour_start_direct = watchface_direct.internal_hour_hand.get(.red).start;

    try std.testing.expectApproxEqAbs(minute_end[0], hour_start_direct[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(minute_end[1], hour_start_direct[1], vector.tolerance);
}

test "init handles full 12-hour cycle" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 60.0) {
        _ = expectInitNonNull(minutes);
    }
}
