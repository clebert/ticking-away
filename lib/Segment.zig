const std = @import("std");

const vector = @import("vector.zig");

const Self = @This();

start: @Vector(2, f32),
end: @Vector(2, f32),

pub const Projection = struct {
    distance_squared: f32,
    normalized_position: f32,
};

pub fn project(self: Self, point: @Vector(2, f32)) Projection {
    const start_to_end = self.end - self.start;
    const start_to_point = point - self.start;

    const length_squared = vector.lengthSquared(start_to_end);

    // floatEps is a numerical floor that keeps 1/length_squared bounded, not a geometric
    // cutoff like vector.tolerance.
    const inverse_length_squared =
        if (length_squared > std.math.floatEps(f32)) 1.0 / length_squared else 0;

    const normalized_position =
        std.math.clamp(@reduce(.Add, start_to_point * start_to_end) * inverse_length_squared, 0, 1);

    const offset_to_point =
        start_to_point - @as(@Vector(2, f32), @splat(normalized_position)) * start_to_end;

    return .{
        .distance_squared = @reduce(.Add, offset_to_point * offset_to_point),
        .normalized_position = normalized_position,
    };
}

test "project point perpendicular to segment midpoint" {
    const segment = Self{ .start = .{ 0.0, 0.0 }, .end = .{ 4.0, 0.0 } };
    const result = segment.project(.{ 2.0, 3.0 });

    try std.testing.expectApproxEqAbs(0.5, result.normalized_position, vector.tolerance);
    try std.testing.expectApproxEqAbs(9.0, result.distance_squared, vector.tolerance);
}

test "project point closest to segment start" {
    const segment = Self{ .start = .{ 0.0, 0.0 }, .end = .{ 4.0, 0.0 } };
    const result = segment.project(.{ -1.0, 1.0 });

    try std.testing.expectApproxEqAbs(0.0, result.normalized_position, vector.tolerance);
    try std.testing.expectApproxEqAbs(2.0, result.distance_squared, vector.tolerance);
}

test "project point closest to segment end" {
    const segment = Self{ .start = .{ 0.0, 0.0 }, .end = .{ 4.0, 0.0 } };
    const result = segment.project(.{ 5.0, 1.0 });

    try std.testing.expectApproxEqAbs(1.0, result.normalized_position, vector.tolerance);
    try std.testing.expectApproxEqAbs(2.0, result.distance_squared, vector.tolerance);
}

test "project point on segment returns zero distance" {
    const segment = Self{ .start = .{ 0.0, 0.0 }, .end = .{ 4.0, 0.0 } };
    const result = segment.project(.{ 1.0, 0.0 });

    try std.testing.expectApproxEqAbs(0.25, result.normalized_position, vector.tolerance);
    try std.testing.expectApproxEqAbs(0.0, result.distance_squared, vector.tolerance);
}

test "project onto zero-length segment returns zero position" {
    const segment = Self{ .start = .{ 2.0, 3.0 }, .end = .{ 2.0, 3.0 } };
    const result = segment.project(.{ 5.0, 7.0 });

    try std.testing.expectApproxEqAbs(0.0, result.normalized_position, vector.tolerance);
    try std.testing.expectApproxEqAbs(25.0, result.distance_squared, vector.tolerance);
}

test "project onto diagonal segment" {
    const segment = Self{ .start = .{ 0.0, 0.0 }, .end = .{ 3.0, 4.0 } };

    // Point (4, 3) projects onto the midpoint of a (3,4) segment:
    // t = dot((4,3),(3,4)) / dot((3,4),(3,4)) = 24/25 = 0.96
    const result = segment.project(.{ 4.0, 3.0 });

    try std.testing.expectApproxEqAbs(0.96, result.normalized_position, vector.tolerance);

    // Closest point on segment: (0.96*3, 0.96*4) = (2.88, 3.84)
    // Distance² = (4-2.88)² + (3-3.84)² = 1.2544 + 0.7056 = 1.96
    try std.testing.expectApproxEqAbs(1.96, result.distance_squared, 1e-4);
}
