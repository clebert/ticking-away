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
    start_radians: f32,
    end_radians: f32,
    wrap_around: bool,
) @Vector(4, f32) {
    const radius_vec: @Vector(2, f32) = @splat(self.radius);
    const start_point = @Vector(2, f32){ @cos(start_radians), @sin(start_radians) } * radius_vec;
    const end_point = @Vector(2, f32){ @cos(end_radians), @sin(end_radians) } * radius_vec;
    const origin: @Vector(2, f32) = .{ 0, 0 };

    var bounds_min = @min(origin, @min(start_point, end_point));
    var bounds_max = @max(origin, @max(start_point, end_point));

    const cardinal_angles = [_]f32{ 0, std.math.pi / 2.0, std.math.pi, 3.0 * std.math.pi / 2.0 };

    const cardinal_offsets = [_]@Vector(2, f32){
        .{ self.radius, 0 },
        .{ 0, self.radius },
        .{ -self.radius, 0 },
        .{ 0, -self.radius },
    };

    inline for (cardinal_angles, cardinal_offsets) |angle, offset| {
        if (angleInSector(angle, start_radians, end_radians, wrap_around)) {
            bounds_min = @min(bounds_min, offset);
            bounds_max = @max(bounds_max, offset);
        }
    }

    return .{ bounds_min[0], bounds_min[1], bounds_max[0], bounds_max[1] };
}

fn angleInSector(angle: f32, start_radians: f32, end_radians: f32, wrap_around: bool) bool {
    return if (wrap_around)
        angle >= start_radians or angle <= end_radians
    else
        angle >= start_radians and angle <= end_radians;
}

test "sectorBounds first quadrant" {
    const scene = Self{ .radius = 1.0, .prism = Prism.init(0.5), .normalized_rainbow_spread = 0.0 };
    const bounds = scene.sectorBounds(0, std.math.pi / 2.0, false);

    // Sector from 0 to π/2 includes cardinals at 0 and π/2
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[3], vector.tolerance);
}

test "sectorBounds third quadrant" {
    const scene = Self{ .radius = 1.0, .prism = Prism.init(0.5), .normalized_rainbow_spread = 0.0 };
    const bounds = scene.sectorBounds(std.math.pi, 3.0 * std.math.pi / 2.0, false);

    // Sector from π to 3π/2 includes cardinals at π and 3π/2
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[3], vector.tolerance);
}

test "sectorBounds wrap-around" {
    const scene = Self{ .radius = 1.0, .prism = Prism.init(0.5), .normalized_rainbow_spread = 0.0 };
    const bounds = scene.sectorBounds(3.0 * std.math.pi / 2.0, std.math.pi / 2.0, true);

    // Sector from 3π/2 to π/2 wrapping through 0 includes cardinals 3π/2, 0, π/2
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[3], vector.tolerance);
}
