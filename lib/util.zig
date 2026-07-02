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

/// Linear edge coverage for analytic antialiasing. Returns 1.0 when the pixel centre
/// lies at least half a pixel inside the edge, 0.0 at least half a pixel outside, and
/// ramps linearly across the one-pixel band between. `inside_distance` is the signed
/// distance from the edge in normalized units (positive inside); `pixels_per_unit` is
/// the viewport scale that converts that distance to pixels.
pub fn edgeCoverage(inside_distance: f32, pixels_per_unit: f32) f32 {
    return std.math.clamp(inside_distance * pixels_per_unit + 0.5, 0.0, 1.0);
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

test "edgeCoverage is full well inside and zero well outside" {
    try std.testing.expectEqual(@as(f32, 1.0), edgeCoverage(1.0, 50.0));
    try std.testing.expectEqual(@as(f32, 0.0), edgeCoverage(-1.0, 50.0));
}

test "edgeCoverage is one half exactly on the edge" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), edgeCoverage(0.0, 50.0), 1e-6);
}

test "edgeCoverage ramps linearly across one pixel" {
    const pixels_per_unit: f32 = 50.0;
    const quarter_pixel = 0.25 / pixels_per_unit;

    try std.testing.expectApproxEqAbs(
        @as(f32, 0.75),
        edgeCoverage(quarter_pixel, pixels_per_unit),
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        edgeCoverage(-quarter_pixel, pixels_per_unit),
        1e-6,
    );
}
