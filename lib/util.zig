const std = @import("std");

pub fn floorClamped(value: f32, max: usize) usize {
    if (std.math.isNan(value)) return 0;
    if (value <= 0) return 0;

    const upper: f32 = @floatFromInt(max);

    if (value >= upper) return max;

    return @intFromFloat(@floor(value));
}

pub fn ceilClamped(value: f32, max: usize) usize {
    if (std.math.isNan(value)) return 0;
    if (value <= 0) return 0;

    const upper: f32 = @floatFromInt(max);

    if (value >= upper) return max;

    return @intFromFloat(@ceil(value));
}

test "floorClamped returns zero for negative values" {
    try std.testing.expectEqual(0, floorClamped(-1.0, 10));
    try std.testing.expectEqual(0, floorClamped(-100.5, 10));
}

test "floorClamped returns zero for zero" {
    try std.testing.expectEqual(0, floorClamped(0.0, 10));
}

test "floorClamped floors a value in range" {
    try std.testing.expectEqual(2, floorClamped(2.7, 10));
    try std.testing.expectEqual(5, floorClamped(5.0, 10));
    try std.testing.expectEqual(0, floorClamped(0.9, 10));
}

test "floorClamped clamps to max" {
    try std.testing.expectEqual(10, floorClamped(10.0, 10));
    try std.testing.expectEqual(10, floorClamped(15.0, 10));
}

test "floorClamped returns zero for NaN" {
    try std.testing.expectEqual(0, floorClamped(std.math.nan(f32), 10));
}

test "ceilClamped returns zero for negative values" {
    try std.testing.expectEqual(0, ceilClamped(-1.0, 10));
    try std.testing.expectEqual(0, ceilClamped(-100.5, 10));
}

test "ceilClamped returns zero for zero" {
    try std.testing.expectEqual(0, ceilClamped(0.0, 10));
}

test "ceilClamped ceils a value in range" {
    try std.testing.expectEqual(3, ceilClamped(2.3, 10));
    try std.testing.expectEqual(5, ceilClamped(5.0, 10));
    try std.testing.expectEqual(1, ceilClamped(0.1, 10));
}

test "ceilClamped clamps to max" {
    try std.testing.expectEqual(10, ceilClamped(10.0, 10));
    try std.testing.expectEqual(10, ceilClamped(15.0, 10));
}

test "ceilClamped returns zero for NaN" {
    try std.testing.expectEqual(0, ceilClamped(std.math.nan(f32), 10));
}
