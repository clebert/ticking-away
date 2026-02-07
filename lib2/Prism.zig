const std = @import("std");

const Ray = @import("Ray.zig");
const Segment = @import("Segment.zig");
const vector = @import("vector.zig");

const Self = @This();

pub const VertexId = enum(u2) {
    apex = 0,
    bottom_right = 1,
    bottom_left = 2,
};

const EdgeId = enum(u2) {
    right = 0, // apex -> bottom_right
    bottom = 1, // bottom_right -> bottom_left
    left = 2, // bottom_left -> apex

    fn getStartVertexId(self: EdgeId) VertexId {
        return @enumFromInt(@intFromEnum(self));
    }

    fn getEndVertexId(self: EdgeId) VertexId {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }
};

vertices: std.EnumArray(VertexId, @Vector(2, f32)),
edges: std.EnumArray(EdgeId, Segment),

/// Creates an equilateral triangle prism centered at the origin (0, 0).
pub fn init(bottom_length: f32) Self {
    std.debug.assert(bottom_length > 0 and bottom_length <= 1.0);

    const sqrt3 = @sqrt(3.0);
    const apex_offset = bottom_length * sqrt3 / 3.0;
    const bottom_offset = bottom_length * sqrt3 / 6.0;
    const half_bottom_length = bottom_length / 2.0;

    const vertices = std.EnumArray(VertexId, @Vector(2, f32)).init(.{
        .apex = .{ 0, -apex_offset },
        .bottom_right = .{ half_bottom_length, bottom_offset },
        .bottom_left = .{ -half_bottom_length, bottom_offset },
    });

    var edges: std.EnumArray(EdgeId, Segment) = undefined;

    inline for (std.meta.tags(EdgeId)) |edge_id| {
        edges.set(edge_id, .{
            .start = vertices.get(edge_id.getStartVertexId()),
            .end = vertices.get(edge_id.getEndVertexId()),
        });
    }

    return .{ .vertices = vertices, .edges = edges };
}

pub fn containsPoint(self: Self, point: @Vector(2, f32)) bool {
    const v0 = self.vertices.get(.apex);
    const v1 = self.vertices.get(.bottom_right);
    const v2 = self.vertices.get(.bottom_left);

    const d0 = vector.cross2d(v1 - v0, point - v0);
    const d1 = vector.cross2d(v2 - v1, point - v1);
    const d2 = vector.cross2d(v0 - v2, point - v2);

    const has_neg = (d0 < 0) or (d1 < 0) or (d2 < 0);
    const has_pos = (d0 > 0) or (d1 > 0) or (d2 > 0);

    return !(has_neg and has_pos);
}

pub fn bounds(self: Self) @Vector(4, f32) {
    var bounds_min: @Vector(2, f32) = @splat(std.math.inf(f32));
    var bounds_max: @Vector(2, f32) = @splat(-std.math.inf(f32));

    inline for (std.meta.tags(VertexId)) |vertex_id| {
        const vertex = self.vertices.get(vertex_id);

        bounds_min = @min(bounds_min, vertex);
        bounds_max = @max(bounds_max, vertex);
    }

    return .{ bounds_min[0], bounds_min[1], bounds_max[0], bounds_max[1] };
}

pub fn intersect(self: Self, ray: Ray) ?Ray.Intersection {
    return Ray.Intersection.closest(
        Ray.Intersection.closest(
            ray.intersectSegment(self.edges.get(.right)),
            ray.intersectSegment(self.edges.get(.bottom)),
        ),
        ray.intersectSegment(self.edges.get(.left)),
    );
}

test "init creates equilateral triangle centered at origin" {
    const bottom_length = 0.8;
    const prism = Self.init(bottom_length);

    const sqrt3 = @sqrt(3.0);
    const expected_apex_offset = bottom_length * sqrt3 / 3.0;
    const expected_bottom_offset = bottom_length * sqrt3 / 6.0;
    const expected_half_bottom_length = bottom_length / 2.0;

    // Verify vertex positions
    const apex = prism.vertices.get(.apex);
    const bottom_right = prism.vertices.get(.bottom_right);
    const bottom_left = prism.vertices.get(.bottom_left);

    try std.testing.expectApproxEqAbs(@as(f32, 0), apex[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(-expected_apex_offset, apex[1], vector.tolerance);

    try std.testing.expectApproxEqAbs(expected_half_bottom_length, bottom_right[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(expected_bottom_offset, bottom_right[1], vector.tolerance);

    try std.testing.expectApproxEqAbs(-expected_half_bottom_length, bottom_left[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(expected_bottom_offset, bottom_left[1], vector.tolerance);

    // Verify edges connect correct vertices
    const right = prism.edges.get(.right);
    const bottom = prism.edges.get(.bottom);
    const left = prism.edges.get(.left);

    try std.testing.expectEqual(apex, right.start);
    try std.testing.expectEqual(bottom_right, right.end);

    try std.testing.expectEqual(bottom_right, bottom.start);
    try std.testing.expectEqual(bottom_left, bottom.end);

    try std.testing.expectEqual(bottom_left, left.start);
    try std.testing.expectEqual(apex, left.end);

    // Verify triangle is equilateral by checking all edges have equal length
    const right_start_to_end = right.end - right.start;
    const bottom_start_to_end = bottom.end - bottom.start;
    const left_start_to_end = left.end - left.start;

    const right_length_squared = @reduce(.Add, right_start_to_end * right_start_to_end);
    const bottom_length_squared = @reduce(.Add, bottom_start_to_end * bottom_start_to_end);
    const left_length_squared = @reduce(.Add, left_start_to_end * left_start_to_end);

    try std.testing.expectApproxEqAbs(right_length_squared, bottom_length_squared, vector.tolerance);
    try std.testing.expectApproxEqAbs(bottom_length_squared, left_length_squared, vector.tolerance);
}

test "bounds returns min/max of vertices" {
    const prism = Self.init(0.8);
    const prism_bounds = prism.bounds();

    const apex = prism.vertices.get(.apex);
    const bottom_right = prism.vertices.get(.bottom_right);
    const bottom_left = prism.vertices.get(.bottom_left);

    // min_x = bottom_left x, min_y = apex y
    try std.testing.expectApproxEqAbs(bottom_left[0], prism_bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(apex[1], prism_bounds[1], vector.tolerance);

    // max_x = bottom_right x, max_y = bottom_right y (== bottom_left y)
    try std.testing.expectApproxEqAbs(bottom_right[0], prism_bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(bottom_right[1], prism_bounds[3], vector.tolerance);
}

test "containsPoint" {
    const prism = Self.init(0.8);

    // Center (origin) is inside
    try std.testing.expect(prism.containsPoint(.{ 0, 0 }));

    // Point far outside
    try std.testing.expect(!prism.containsPoint(.{ 1, 1 }));

    // Vertex is on boundary (cross products are zero)
    try std.testing.expect(prism.containsPoint(prism.vertices.get(.apex)));
}
