const std = @import("std");

const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Ray = @import("Ray.zig");
const Segment = @import("Segment.zig");
const Time = @import("Time.zig");
const vector = @import("vector.zig");

const Self = @This();

const hour_arc: f32 = std.math.pi / 6.0; // 2π/12 = π/6 ≈ 30° (one hour moves 30°)
const apex_angle: f32 = -std.math.pi / 2.0; // −π/2 (−90°, 12 o'clock)
const rainbow_max_spread_radians: f32 = std.math.pi / 6.0;

prism: Prism,
external_minute_hand: Segment,
internal_minute_hand: ?Segment,
internal_hour_hand: std.EnumArray(Rainbow.ColorId, Segment),
external_hour_hand: std.EnumArray(Rainbow.ColorId, Segment),

pub fn init(
    time: Time,
    prism_normalized_size: f32,
    prism_rotating: bool,
    rainbow_normalized_spread: f32,
) Self {
    var prism = Prism.init(prism_normalized_size);

    std.debug.assert(
        rainbow_normalized_spread >= 0.0 and rainbow_normalized_spread <= 1.0,
    );

    const hour_count: usize = @intFromFloat(time.total_minutes / 60.0);
    const hour: u4 = @intCast(@mod(hour_count, 12));
    const minute = time.total_minutes - @as(f32, @floatFromInt(hour_count)) * 60.0;
    const minute_angle = apex_angle + (minute / 60.0) * std.math.tau;

    const hour_angle = apex_angle + (@as(f32, @floatFromInt(hour)) / 12.0) *
        std.math.tau + (minute / 60.0) * hour_arc;

    const hour_ray_center = Ray.init(.{ 0, 0 }, .{ @cos(hour_angle), @sin(hour_angle) });

    const minute_position: @Vector(2, f32) = .{ @cos(minute_angle), @sin(minute_angle) };

    var entry_point: @Vector(2, f32) = undefined;
    var internal_minute_hand: ?Segment = undefined;
    var internal_hour_hand_start: @Vector(2, f32) = undefined;

    if (prism_rotating) {
        // π/6 aligns the right edge perpendicular to the minute hand direction
        prism = prism.rotated(minute_angle + std.math.pi / 6.0);

        // Light enters at the midpoint of the right edge
        entry_point = (prism.vertices.get(.apex) + prism.vertices.get(.bottom_right)) /
            @as(@Vector(2, f32), @splat(2.0));

        const right_edge = prism.edges.get(.right);
        const bounce_vertex = prism.vertices.get(.bottom_left);

        internal_minute_hand = if (hour_ray_center.intersectSegment(right_edge) != null) .{
            .start = entry_point,
            .end = bounce_vertex,
        } else null;

        internal_hour_hand_start = if (internal_minute_hand != null) bounce_vertex else entry_point;
    } else {
        const minute_ray = Ray.init(minute_position, .{ 0, 0 });
        const hit = (prism.intersect(minute_ray) orelse unreachable).hit;

        entry_point = hit;

        internal_minute_hand = if (bouncingVertexId(hour, minute)) |vertex_id| .{
            .start = hit,
            .end = prism.vertices.get(vertex_id),
        } else null;

        internal_hour_hand_start = if (internal_minute_hand) |hand| hand.end else hit;
    }

    const external_minute_hand: Segment = .{
        .start = minute_position,
        .end = entry_point,
    };

    const spread_radians = rainbow_normalized_spread * rainbow_max_spread_radians;

    var internal_hour_hand: std.EnumArray(Rainbow.ColorId, Segment) = undefined;
    var external_hour_hand: std.EnumArray(Rainbow.ColorId, Segment) = undefined;

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const color_index: f32 = @floatFromInt(@intFromEnum(color_id));

        const normalized_position =
            (color_index + 0.5) / @as(f32, @floatFromInt(Rainbow.color_count));

        const color_angle = hour_angle + (0.5 - normalized_position) * spread_radians;

        const hour_ray = Ray.init(.{ 0, 0 }, .{ @cos(color_angle), @sin(color_angle) });
        const hour_prism_intersection = prism.intersect(hour_ray) orelse unreachable;

        const hour_boundary_intersection =
            hour_ray.intersectCircle() orelse unreachable;

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
        .prism = prism,
        .external_minute_hand = external_minute_hand,
        .internal_minute_hand = internal_minute_hand,
        .internal_hour_hand = internal_hour_hand,
        .external_hour_hand = external_hour_hand,
    };
}

fn bouncingVertexId(hour: u4, minute: f32) ?Prism.VertexId {
    const margin: f32 = 0.5;

    switch (hour) {
        0, 1, 2 => if (minute < 20.0 + margin or minute > 60.0 - margin) return .bottom_left,
        3 => if (minute < 20.0 + margin) return .bottom_left,
        4, 5, 6, 7 => if (minute > 20.0 - margin and minute < 40.0 + margin) return .apex,
        8 => if (minute > 40.0 - margin) return .bottom_right,
        9, 10, 11 => if (minute < 0.0 + margin or minute > 40.0 - margin) return .bottom_right,
        else => unreachable,
    }

    return null;
}

const test_prism_normalized_size: f32 = 0.8;
const test_rainbow_spread: f32 = 0.5;

test "init at 12:00" {
    _ = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );
}

test "init at 3:15" {
    _ = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );
}

test "init minute hand starts on circle boundary" {
    const watchface = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );

    const start_distance = vector.length(watchface.external_minute_hand.start);

    try std.testing.expectApproxEqAbs(1.0, start_distance, vector.tolerance);
}

test "init minute hand ends on prism edge" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );

    const end = clock.external_minute_hand.end;
    const ray = Ray.init(clock.external_minute_hand.start, end);
    const intersection = clock.prism.intersect(ray).?;

    try std.testing.expectApproxEqAbs(intersection.hit[0], end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(intersection.hit[1], end[1], vector.tolerance);
}

test "init all hour hand colors share same internal start" {
    const watchface = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );

    const first = watchface.internal_hour_hand.get(.red).start;

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const start = watchface.internal_hour_hand.get(color_id).start;

        try std.testing.expectApproxEqAbs(first[0], start[0], vector.tolerance);
        try std.testing.expectApproxEqAbs(first[1], start[1], vector.tolerance);
    }
}

test "init external hour hand endpoints lie on circle boundary" {
    const watchface = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const end = watchface.external_hour_hand.get(color_id).end;
        const distance = vector.length(end);

        try std.testing.expectApproxEqAbs(1.0, distance, vector.tolerance);
    }
}

test "init internal minute hand bounces when hour exits entry edge" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );

    const hand = clock.internal_minute_hand.?;
    const hour_start = clock.internal_hour_hand.get(.red).start;

    try std.testing.expectApproxEqAbs(hand.end[0], hour_start[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(hand.end[1], hour_start[1], vector.tolerance);
}

test "init internal minute hand is null when hour exits different edge" {
    const clock = Self.init(
        .{ .total_minutes = 360.0 },
        test_prism_normalized_size,
        true,
        test_rainbow_spread,
    );

    try std.testing.expectEqual(null, clock.internal_minute_hand);

    const hour_start = clock.internal_hour_hand.get(.red).start;
    const entry = clock.external_minute_hand.end;

    try std.testing.expectApproxEqAbs(entry[0], hour_start[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(entry[1], hour_start[1], vector.tolerance);
}

test "init handles full 12-hour cycle rotating" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 60.0) {
        _ = Self.init(
            .{ .total_minutes = minutes },
            test_prism_normalized_size,
            true,
            test_rainbow_spread,
        );
    }
}

test "init handles full 12-hour cycle static" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 60.0) {
        _ = Self.init(
            .{ .total_minutes = minutes },
            test_prism_normalized_size,
            false,
            test_rainbow_spread,
        );
    }
}

test "init static internal_minute_hand is non-null when bouncing" {
    const clock = Self.init(
        .{ .total_minutes = 10.0 },
        test_prism_normalized_size,
        false,
        test_rainbow_spread,
    );

    try std.testing.expect(clock.internal_minute_hand != null);
}

test "init static internal_minute_hand is null when not bouncing" {
    const clock = Self.init(
        .{ .total_minutes = 30.0 },
        test_prism_normalized_size,
        false,
        test_rainbow_spread,
    );

    try std.testing.expectEqual(null, clock.internal_minute_hand);
}

test "init static internal_minute_hand ends at prism vertex when bouncing" {
    const clock = Self.init(
        .{ .total_minutes = 10.0 },
        test_prism_normalized_size,
        false,
        test_rainbow_spread,
    );

    const hand = clock.internal_minute_hand.?;
    const expected = clock.prism.vertices.get(.bottom_left);

    try std.testing.expectApproxEqAbs(expected[0], hand.end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(expected[1], hand.end[1], vector.tolerance);
}
