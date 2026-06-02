const std = @import("std");

const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Segment = @import("Segment.zig");
const Time = @import("Time.zig");
const vector = @import("vector.zig");

const Self = @This();

const hour_arc: f32 = std.math.pi / 6.0; // 30° per hour-step on the dial
const apex_angle: f32 = -std.math.pi / 2.0; // 12 o'clock (apex, top of dial)
const rainbow_max_spread_radians: f32 = std.math.pi / 6.0;

prism: Prism,
minute_hand: Segment,
hour_hand: std.EnumArray(Rainbow.ColorId, Segment),

pub fn init(time: Time, prism_normalized_size: f32, rainbow_normalized_spread: f32) Self {
    const prism = Prism.init(prism_normalized_size);

    std.debug.assert(
        rainbow_normalized_spread >= 0.0 and rainbow_normalized_spread <= 1.0,
    );

    const hour_count: usize = @intFromFloat(time.total_minutes / 60.0);
    const hour: u4 = @intCast(@mod(hour_count, 12));
    const minute = time.total_minutes - @as(f32, @floatFromInt(hour_count)) * 60.0;
    const minute_angle = apex_angle + (minute / 60.0) * std.math.tau;

    const minute_hand: Segment = .{
        .start = .{ @cos(minute_angle), @sin(minute_angle) },
        .end = .{ 0, 0 },
    };

    const hour_angle = apex_angle + (@as(f32, @floatFromInt(hour)) / 12.0) *
        std.math.tau + (minute / 60.0) * hour_arc;

    const spread_radians = rainbow_normalized_spread * rainbow_max_spread_radians;

    var hour_hand: std.EnumArray(Rainbow.ColorId, Segment) = undefined;

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const color_index: f32 = @floatFromInt(@intFromEnum(color_id));

        const normalized_position =
            (color_index + 0.5) / @as(f32, @floatFromInt(Rainbow.color_count));

        const color_angle = hour_angle + (0.5 - normalized_position) * spread_radians;

        hour_hand.set(color_id, .{
            .start = .{ 0, 0 },
            .end = .{ @cos(color_angle), @sin(color_angle) },
        });
    }

    return .{
        .prism = prism,
        .minute_hand = minute_hand,
        .hour_hand = hour_hand,
    };
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

    const start_distance = vector.length(clock.minute_hand.start);

    try std.testing.expectApproxEqAbs(1.0, start_distance, vector.tolerance);
}

test "init minute hand ends at origin" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), clock.minute_hand.end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), clock.minute_hand.end[1], vector.tolerance);
}

test "init hour hand starts at origin" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const start = clock.hour_hand.get(color_id).start;

        try std.testing.expectApproxEqAbs(@as(f32, 0.0), start[0], vector.tolerance);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), start[1], vector.tolerance);
    }
}

test "init hour hand endpoints lie on circle boundary" {
    const clock = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
    );

    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const end = clock.hour_hand.get(color_id).end;
        const distance = vector.length(end);

        try std.testing.expectApproxEqAbs(1.0, distance, vector.tolerance);
    }
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
