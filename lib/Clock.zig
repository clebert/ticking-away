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

pub fn init(time: Time, prism_normalized_size: f32, rainbow_normalized_spread: f32) Self {
    const prism = Prism.init(prism_normalized_size);

    std.debug.assert(
        rainbow_normalized_spread >= 0.0 and rainbow_normalized_spread <= 1.0,
    );

    const hour_count: usize = @intFromFloat(time.total_minutes / 60.0);
    const hour: u4 = @intCast(@mod(hour_count, 12));
    const minute = time.total_minutes - @as(f32, @floatFromInt(hour_count)) * 60.0;
    const minute_angle = apex_angle + (minute / 60.0) * std.math.tau;
    const minute_position: @Vector(2, f32) = .{ @cos(minute_angle), @sin(minute_angle) };
    const minute_ray = Ray.init(minute_position, .{ 0, 0 });
    const minute_prism_intersection = prism.intersect(minute_ray) orelse unreachable;

    const external_minute_hand: Segment = .{
        .start = minute_position,
        .end = minute_prism_intersection.hit,
    };

    const internal_minute_hand: ?Segment = if (computeBounce(hour, minute)) |bounce| .{
        .start = external_minute_hand.end,
        .end = bounce.position(prism),
    } else null;

    const internal_hour_hand_start =
        if (internal_minute_hand) |hand| hand.end else external_minute_hand.end;

    const hour_angle = apex_angle + (@as(f32, @floatFromInt(hour)) / 12.0) *
        std.math.tau + (minute / 60.0) * hour_arc;

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

const Bounce = union(enum) {
    vertex: Prism.VertexId,
    edge: Prism.EdgeId,

    fn position(self: Bounce, prism: Prism) @Vector(2, f32) {
        return switch (self) {
            .vertex => |vertex_id| prism.vertices.get(vertex_id),
            .edge => |edge_id| {
                const edge = prism.edges.get(edge_id);

                return (edge.start + edge.end) / @as(@Vector(2, f32), @splat(2.0));
            },
        };
    }
};

fn computeBounce(hour: u4, minute: f32) ?Bounce {
    const margin: f32 = 0.5;

    switch (hour) {
        0, 1, 2 => if (minute < 20.0 + margin or minute > 60.0 - margin) return .{
            .vertex = .bottom_left,
        },
        3 => if (minute < 15.0 + margin) return .{
            .vertex = .bottom_left,
        } else if (minute < 25.0 + margin) return .{
            .edge = .left,
        },
        4, 5, 6, 7 => if (minute > 20.0 - margin and minute < 40.0 + margin) return .{
            .vertex = .apex,
        },
        8 => if (minute > 40.0 - margin) return .{
            .vertex = .bottom_right,
        },
        9, 10, 11 => if (minute < 0.0 + margin or minute > 40.0 - margin) return .{
            .vertex = .bottom_right,
        },
        else => unreachable,
    }

    return null;
}

const test_prism_normalized_size: f32 = 0.8;
const test_rainbow_spread: f32 = 0.5;

test "init at 12:00" {
    _ = Self.init(.{ .total_minutes = 0.0 }, test_prism_normalized_size, test_rainbow_spread);
}

test "init at 3:15" {
    _ = Self.init(.{ .total_minutes = 195.0 }, test_prism_normalized_size, test_rainbow_spread);
}

test "init minute hand starts on circle boundary" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    const start_distance = vector.length(clock.external_minute_hand.start);

    try std.testing.expectApproxEqAbs(1.0, start_distance, vector.tolerance);
}

test "init minute hand ends on prism edge" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    const end = clock.external_minute_hand.end;
    const ray = Ray.init(clock.external_minute_hand.start, end);
    const intersection = clock.prism.intersect(ray).?;

    try std.testing.expectApproxEqAbs(intersection.hit[0], end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(intersection.hit[1], end[1], vector.tolerance);
}

test "init internal_minute_hand is non-null when bouncing" {
    // hour=0, minute=10 → bouncingVertex returns .bottom_left
    const clock = Self.init(
        .{ .total_minutes = 10.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    try std.testing.expect(clock.internal_minute_hand != null);
}

test "init internal_minute_hand is null when not bouncing" {
    // hour=0, minute=30 → bouncingVertex returns null
    const clock = Self.init(
        .{ .total_minutes = 30.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    try std.testing.expectEqual(null, clock.internal_minute_hand);
}

test "init internal_minute_hand ends at prism vertex when bouncing" {
    // hour=0, minute=10 → bounces to .bottom_left
    const clock = Self.init(
        .{ .total_minutes = 10.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    const hand = clock.internal_minute_hand.?;
    const expected = clock.prism.vertices.get(.bottom_left);

    try std.testing.expectApproxEqAbs(expected[0], hand.end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(expected[1], hand.end[1], vector.tolerance);
}

test "init all hour hand colors share same internal start" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    const first = clock.internal_hour_hand.get(.red).start;

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const start = clock.internal_hour_hand.get(color_id).start;

        try std.testing.expectApproxEqAbs(first[0], start[0], vector.tolerance);
        try std.testing.expectApproxEqAbs(first[1], start[1], vector.tolerance);
    }
}

test "init external hour hand endpoints lie on circle boundary" {
    const clock = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const end = clock.external_hour_hand.get(color_id).end;
        const distance = vector.length(end);

        try std.testing.expectApproxEqAbs(1.0, distance, vector.tolerance);
    }
}

test "init internal hour hand start matches minute hand chain" {
    // When bouncing: internal_hour_hand start == internal_minute_hand end
    const clock_bouncing = Self.init(
        .{ .total_minutes = 10.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    const bounce_hand = clock_bouncing.internal_minute_hand.?;
    const hour_start = clock_bouncing.internal_hour_hand.get(.red).start;

    try std.testing.expectApproxEqAbs(bounce_hand.end[0], hour_start[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(bounce_hand.end[1], hour_start[1], vector.tolerance);

    // When not bouncing: internal_hour_hand start == external_minute_hand end
    const clock_direct = Self.init(
        .{ .total_minutes = 30.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    const minute_end = clock_direct.external_minute_hand.end;
    const hour_start_direct = clock_direct.internal_hour_hand.get(.red).start;

    try std.testing.expectApproxEqAbs(minute_end[0], hour_start_direct[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(minute_end[1], hour_start_direct[1], vector.tolerance);
}

test "init handles full 12-hour cycle" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 60.0) {
        _ = Self.init(
            .{ .total_minutes = minutes },
            test_prism_normalized_size,
            test_rainbow_spread,
        );
    }
}
