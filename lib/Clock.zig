const std = @import("std");

const Prism = @import("Prism.zig");
const Segment = @import("Segment.zig");
const Time = @import("Time.zig");
const vector = @import("vector.zig");

const Self = @This();

const hour_arc: f32 = std.math.pi / 6.0; // 30° per hour-step on the dial
const apex_angle: f32 = -std.math.pi / 2.0; // 12 o'clock (apex, top of dial)
const rainbow_max_spread_radians: f32 = std.math.pi / 6.0;

prism: Prism,
minute_hand: Segment,
hour_center: Segment,
rainbow_start: Segment,
rainbow_end: Segment,

pub fn init(
    time: Time,
    prism_normalized_size: f32,
    rainbow_normalized_spread: f32,
    color_count: usize,
) Self {
    const prism = Prism.init(prism_normalized_size);

    std.debug.assert(rainbow_normalized_spread >= 0.0 and rainbow_normalized_spread <= 1.0);
    std.debug.assert(color_count >= 2);

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

    // The hour hand fans into the rainbow, symmetric about hour_angle: hour_center is the
    // hand's true aim, and the first and last band centres sit at ±half_spread. Spectrum
    // fills the interior bands between the two extremes, so only these three rays matter.
    const count: f32 = @floatFromInt(color_count);
    const half_spread = (0.5 - 0.5 / count) * spread_radians;

    return .{
        .prism = prism,
        .minute_hand = minute_hand,
        .hour_center = ray(hour_angle),
        .rainbow_start = ray(hour_angle + half_spread),
        .rainbow_end = ray(hour_angle - half_spread),
    };
}

fn ray(angle: f32) Segment {
    return .{ .start = .{ 0, 0 }, .end = .{ @cos(angle), @sin(angle) } };
}

const test_prism_normalized_size: f32 = 0.8;
const test_rainbow_spread: f32 = 0.5;
const test_color_count: usize = 6;

test "init at 12:00" {
    _ = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
        test_color_count,
    );
}

test "init at 3:15" {
    _ = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
        test_color_count,
    );
}

test "init minute hand starts on circle boundary" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
        test_color_count,
    );

    const start_distance = vector.length(clock.minute_hand.start);

    try std.testing.expectApproxEqAbs(1.0, start_distance, vector.tolerance);
}

test "init minute hand ends at origin" {
    const clock = Self.init(
        .{ .total_minutes = 0.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
        test_color_count,
    );

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), clock.minute_hand.end[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), clock.minute_hand.end[1], vector.tolerance);
}

test "init hour rays start at origin and end on the circle boundary" {
    const clock = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
        test_color_count,
    );

    for ([_]Segment{ clock.hour_center, clock.rainbow_start, clock.rainbow_end }) |hand| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), hand.start[0], vector.tolerance);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), hand.start[1], vector.tolerance);
        try std.testing.expectApproxEqAbs(1.0, vector.length(hand.end), vector.tolerance);
    }
}

test "init hour center bisects the band fan" {
    const clock = Self.init(
        .{ .total_minutes = 195.0 },
        test_prism_normalized_size,
        test_rainbow_spread,
        test_color_count,
    );

    const center = clock.hour_center.end;

    try std.testing.expectApproxEqAbs(1.0, vector.length(center), vector.tolerance);

    // The extreme band rays are symmetric about hour_angle, so their bisector is the
    // centre — independent of the band count.
    const bisector = vector.normalize(clock.rainbow_start.end + clock.rainbow_end.end);

    try std.testing.expectApproxEqAbs(bisector[0], center[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(bisector[1], center[1], vector.tolerance);
}

test "init handles full 12-hour cycle" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 60.0) {
        _ = Self.init(
            .{ .total_minutes = minutes },
            test_prism_normalized_size,
            test_rainbow_spread,
            test_color_count,
        );
    }
}
