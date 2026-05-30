const std = @import("std");

const Segment = @import("Segment.zig");
const vector = @import("vector.zig");

const Self = @This();

origin: @Vector(2, f32),
direction: @Vector(2, f32),

pub fn init(origin: @Vector(2, f32), target: @Vector(2, f32)) Self {
    return .{
        .origin = origin,
        .direction = vector.normalize(target - origin),
    };
}

pub const Intersection = struct {
    distance: f32,
    hit: @Vector(2, f32),

    pub fn closest(a: ?Intersection, b: ?Intersection) ?Intersection {
        const a_val = a orelse return b;
        const b_val = b orelse return a;

        return if (a_val.distance <= b_val.distance) a else b;
    }
};

pub fn intersectSegment(self: Self, segment: Segment) ?Intersection {
    std.debug.assert(vector.isNormalized(self.direction));

    const start_to_end = segment.end - segment.start;

    // Rotated 90° counterclockwise.
    const ray_normal: @Vector(2, f32) = .{ -self.direction[1], self.direction[0] };

    // Zero when ray and segment are parallel; larger values mean more perpendicular.
    const denominator = vector.dot(start_to_end, ray_normal);

    if (@abs(denominator) < vector.tolerance) return null;

    const start_to_origin = self.origin - segment.start;
    const distance = vector.cross2d(start_to_end, start_to_origin) / denominator;

    if (distance < vector.tolerance) return null;

    const normalized_position_unclamped =
        vector.dot(start_to_origin, ray_normal) / denominator;

    if (normalized_position_unclamped < -vector.tolerance or
        normalized_position_unclamped > 1.0 + vector.tolerance) return null;

    const normalized_position = std.math.clamp(normalized_position_unclamped, 0.0, 1.0);
    const hit = segment.start + start_to_end * @as(@Vector(2, f32), @splat(normalized_position));

    return .{ .distance = distance, .hit = hit };
}

test "intersectSegment returns intersection at segment midpoint" {
    const ray = Self.init(.{ -0.5, 0.0 }, .{ 0.5, 0.0 });
    const segment = Segment{ .start = .{ 0.0, -0.5 }, .end = .{ 0.0, 0.5 } };

    const intersection = ray.intersectSegment(segment).?;

    try std.testing.expectApproxEqAbs(0.5, intersection.distance, vector.tolerance);
    try std.testing.expectApproxEqAbs(0.0, intersection.hit[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(0.0, intersection.hit[1], vector.tolerance);
}

test "intersectSegment returns intersection at segment start" {
    const ray = Self.init(.{ -0.5, -0.5 }, .{ 0.5, -0.5 });
    const segment = Segment{ .start = .{ 0.0, -0.5 }, .end = .{ 0.0, 0.5 } };

    const intersection = ray.intersectSegment(segment).?;

    try std.testing.expectApproxEqAbs(0.5, intersection.distance, vector.tolerance);
    try std.testing.expectApproxEqAbs(0.0, intersection.hit[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(-0.5, intersection.hit[1], vector.tolerance);
}

test "intersectSegment returns intersection at segment end" {
    const ray = Self.init(.{ -0.5, 0.5 }, .{ 0.5, 0.5 });
    const segment = Segment{ .start = .{ 0.0, -0.5 }, .end = .{ 0.0, 0.5 } };

    const intersection = ray.intersectSegment(segment).?;

    try std.testing.expectApproxEqAbs(0.5, intersection.distance, vector.tolerance);
    try std.testing.expectApproxEqAbs(0.0, intersection.hit[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(0.5, intersection.hit[1], vector.tolerance);
}

test "intersectSegment returns null when ray misses segment" {
    const ray = Self.init(.{ -0.5, 0.0 }, .{ 0.5, 0.0 });
    const segment = Segment{ .start = .{ 0.0, 0.5 }, .end = .{ 0.0, 0.9 } };

    const intersection = ray.intersectSegment(segment);

    try std.testing.expectEqual(null, intersection);
}

test "intersectSegment returns null when ray points away from segment" {
    const ray = Self.init(.{ 0.5, 0.0 }, .{ 0.9, 0.0 });
    const segment = Segment{ .start = .{ 0.0, -0.5 }, .end = .{ 0.0, 0.5 } };

    const intersection = ray.intersectSegment(segment);

    try std.testing.expectEqual(null, intersection);
}

test "intersectSegment returns null when ray and segment are parallel" {
    const ray = Self.init(.{ -0.5, 0.0 }, .{ 0.5, 0.0 });
    const segment = Segment{ .start = .{ -0.5, 0.5 }, .end = .{ 0.5, 0.5 } };

    const intersection = ray.intersectSegment(segment);

    try std.testing.expectEqual(null, intersection);
}

test "intersectSegment handles diagonal ray and segment" {
    const ray = Self.init(.{ -0.5, -0.5 }, .{ 0.5, 0.5 });
    const segment = Segment{ .start = .{ -0.5, 0.5 }, .end = .{ 0.5, -0.5 } };

    const intersection = ray.intersectSegment(segment).?;

    try std.testing.expectApproxEqAbs(0.0, intersection.hit[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(0.0, intersection.hit[1], vector.tolerance);
}

test "intersectSegment returns null when ray origin is on segment" {
    const ray = Self.init(.{ 0.0, 0.0 }, .{ 0.5, 0.0 });
    const segment = Segment{ .start = .{ 0.0, -0.5 }, .end = .{ 0.0, 0.5 } };

    const intersection = ray.intersectSegment(segment);

    try std.testing.expectEqual(null, intersection);
}
