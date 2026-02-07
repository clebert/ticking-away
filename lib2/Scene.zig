const std = @import("std");

const Prism = @import("Prism.zig");
const vector = @import("vector.zig");

const Self = @This();

radius: f32,
prism: Prism,
normalized_rainbow_spread: f32,

pub const Side = enum { internal, external };

pub fn containsPoint(self: Self, side: Side, point: @Vector(2, f32)) bool {
    return switch (side) {
        .internal => self.prism.containsPoint(point),
        .external => @reduce(.Add, point * point) <= self.radius * self.radius and
            !self.prism.containsPoint(point),
    };
}

pub fn sectorBounds(
    self: Self,
    direction_start: @Vector(2, f32),
    direction_end: @Vector(2, f32),
) @Vector(4, f32) {
    const radius_vec: @Vector(2, f32) = @splat(self.radius);
    const start_point = direction_start * radius_vec;
    const end_point = direction_end * radius_vec;
    const origin: @Vector(2, f32) = .{ 0, 0 };

    var bounds_min = @min(origin, @min(start_point, end_point));
    var bounds_max = @max(origin, @max(start_point, end_point));

    const cardinal_directions = [_]@Vector(2, f32){
        .{ 1, 0 },
        .{ 0, 1 },
        .{ -1, 0 },
        .{ 0, -1 },
    };

    const cardinal_offsets = [_]@Vector(2, f32){
        .{ self.radius, 0 },
        .{ 0, self.radius },
        .{ -self.radius, 0 },
        .{ 0, -self.radius },
    };

    inline for (cardinal_directions, cardinal_offsets) |cardinal, offset| {
        if (directionInSector(cardinal, direction_start, direction_end)) {
            bounds_min = @min(bounds_min, offset);
            bounds_max = @max(bounds_max, offset);
        }
    }

    return .{ bounds_min[0], bounds_min[1], bounds_max[0], bounds_max[1] };
}

/// Tests if a direction lies within the CCW sector from start to end (span <= π).
fn directionInSector(
    direction: @Vector(2, f32),
    sector_start: @Vector(2, f32),
    sector_end: @Vector(2, f32),
) bool {
    return vector.cross2d(sector_start, direction) >= 0 and
        vector.cross2d(direction, sector_end) >= 0;
}

test "sectorBounds first quadrant" {
    const scene = Self{ .radius = 1.0, .prism = Prism.init(0.5), .normalized_rainbow_spread = 0.0 };
    const bounds = scene.sectorBounds(.{ 1, 0 }, .{ 0, 1 });

    // CCW sector from (1,0) to (0,1) includes cardinals at 0 and π/2
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[3], vector.tolerance);
}

test "sectorBounds third quadrant" {
    const scene = Self{ .radius = 1.0, .prism = Prism.init(0.5), .normalized_rainbow_spread = 0.0 };
    const bounds = scene.sectorBounds(.{ -1, 0 }, .{ 0, -1 });

    // CCW sector from (-1,0) to (0,-1) includes cardinals at π and 3π/2
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[3], vector.tolerance);
}

test "sectorBounds wrap-around" {
    const scene = Self{ .radius = 1.0, .prism = Prism.init(0.5), .normalized_rainbow_spread = 0.0 };
    const bounds = scene.sectorBounds(.{ 0, -1 }, .{ 0, 1 });

    // CCW sector from (0,-1) to (0,1) wrapping through 0 includes cardinals 3π/2, 0, π/2
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[3], vector.tolerance);
}
