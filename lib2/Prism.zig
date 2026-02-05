const std = @import("std");

const Ray = @import("Ray.zig");
const Segment = @import("Segment.zig");
const vector = @import("vector.zig");

pub const VertexId = enum(u2) {
    apex = 0,
    bottom_right = 1,
    bottom_left = 2,

    pub fn getOppositeEdgeId(self: VertexId) EdgeId {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }
};

pub const EdgeId = enum(u2) {
    right = 0, // apex -> bottom_right
    bottom = 1, // bottom_right -> bottom_left
    left = 2, // bottom_left -> apex

    pub fn getStartVertexId(self: EdgeId) VertexId {
        return @enumFromInt(@intFromEnum(self));
    }

    pub fn getEndVertexId(self: EdgeId) VertexId {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }

    pub fn getOppositeVertexId(self: EdgeId) VertexId {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 2) % 3);
    }

    pub fn touchesVertex(self: EdgeId, vertex_id: VertexId) bool {
        return vertex_id == self.getStartVertexId() or vertex_id == self.getEndVertexId();
    }
};

const Self = @This();

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
