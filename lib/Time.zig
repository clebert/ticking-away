const std = @import("std");

const Self = @This();

total_minutes: f32,

pub fn init(hour: u32, minute: f32) Self {
    return .{ .total_minutes = @as(f32, @floatFromInt(hour % 12)) * 60.0 + @mod(minute, 60.0) };
}

test "init at 12:00" {
    const time = init(0, 0.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), time.total_minutes, 1e-6);
}

test "init at 3:30" {
    const time = init(3, 30.0);

    try std.testing.expectApproxEqAbs(@as(f32, 210.0), time.total_minutes, 1e-6);
}

test "init wraps hours above 12" {
    const time = init(14, 15.0);
    const expected = init(2, 15.0);

    try std.testing.expectApproxEqAbs(expected.total_minutes, time.total_minutes, 1e-6);
}

test "init wraps minutes above 60" {
    const time = init(1, 75.0);

    try std.testing.expectApproxEqAbs(@as(f32, 75.0), time.total_minutes, 1e-6);
}
