const std = @import("std");

const frame = @import("frame.zig");
const line = @import("line.zig");
const vec2 = @import("vec2.zig");

pub const Vertex = enum(u2) {
    apex = 0,
    bottom_right = 1,
    bottom_left = 2,

    pub fn oppositeEdge(self: Vertex) Edge {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }
};

pub const Edge = enum(u2) {
    right = 0, // apex -> bottom_right
    bottom = 1, // bottom_right -> bottom_left
    left = 2, // bottom_left -> apex

    pub fn startVertex(self: Edge) Vertex {
        return @enumFromInt(@intFromEnum(self));
    }

    pub fn endVertex(self: Edge) Vertex {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }

    pub fn oppositeVertex(self: Edge) Vertex {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 2) % 3);
    }

    pub fn touchesVertex(self: Edge, vertex: Vertex) bool {
        return vertex == self.startVertex() or vertex == self.endVertex();
    }
};

const Self = @This();

vertices: std.EnumArray(Vertex, vec2.Vec2),
edges: std.EnumArray(Edge, line.Segment),

pub fn init(center: vec2.Vec2, base_width: f32) Self {
    const sqrt3 = @sqrt(3.0);
    const apex_offset = base_width * sqrt3 / 3.0;
    const base_offset = base_width * sqrt3 / 6.0;
    const half_base = base_width / 2.0;

    const vertices = std.EnumArray(Vertex, vec2.Vec2).init(.{
        .apex = vec2.xy(center[0], center[1] - apex_offset),
        .bottom_right = vec2.xy(center[0] + half_base, center[1] + base_offset),
        .bottom_left = vec2.xy(center[0] - half_base, center[1] + base_offset),
    });

    var edges: std.EnumArray(Edge, line.Segment) = undefined;
    inline for (std.meta.tags(Edge)) |edge| {
        edges.set(edge, line.Segment.init(
            vertices.get(edge.startVertex()),
            vertices.get(edge.endVertex()),
        ));
    }

    return .{ .vertices = vertices, .edges = edges };
}

pub fn scanlineRange(self: Self, y: f32) ?frame.Range {
    const t = self.vertices.get(.apex);
    const m = self.vertices.get(.bottom_left);
    const b = self.vertices.get(.bottom_right);

    if (y < t[1] or y > b[1]) return null;

    const eps = std.math.floatEps(f32);
    const in_upper = y < m[1];

    const long_t = if (b[1] - t[1] > eps) (y - t[1]) / (b[1] - t[1]) else 0;
    const x_long = t[0] + long_t * (b[0] - t[0]);

    const x_short = if (in_upper) blk: {
        const short_t = if (m[1] - t[1] > eps) (y - t[1]) / (m[1] - t[1]) else 0;
        break :blk t[0] + short_t * (m[0] - t[0]);
    } else blk: {
        const short_t = if (b[1] - m[1] > eps) (y - m[1]) / (b[1] - m[1]) else 0;
        break :blk m[0] + short_t * (b[0] - m[0]);
    };

    return .{ .x_min = x_short, .x_max = x_long };
}

pub fn containsPoint(self: Self, px: f32, py: f32) bool {
    const v0 = self.vertices.get(.apex);
    const v1 = self.vertices.get(.bottom_right);
    const v2 = self.vertices.get(.bottom_left);

    // Barycentric containment test
    const denom = (v1[1] - v2[1]) * (v0[0] - v2[0]) + (v2[0] - v1[0]) * (v0[1] - v2[1]);
    if (@abs(denom) < 1e-9) return false;

    const inv_denom = 1.0 / denom;
    const a = ((v1[1] - v2[1]) * (px - v2[0]) + (v2[0] - v1[0]) * (py - v2[1])) * inv_denom;
    const b = ((v2[1] - v0[1]) * (px - v2[0]) + (v0[0] - v2[0]) * (py - v2[1])) * inv_denom;

    return a >= 0 and b >= 0 and (a + b) <= 1;
}

pub fn minY(self: Self) f32 {
    return self.vertices.get(.apex)[1];
}

pub fn maxY(self: Self) f32 {
    return self.vertices.get(.bottom_right)[1];
}

pub fn centroid(self: Self) vec2.Vec2 {
    const v0 = self.vertices.get(.apex);
    const v1 = self.vertices.get(.bottom_right);
    const v2 = self.vertices.get(.bottom_left);
    return vec2.xy(
        (v0[0] + v1[0] + v2[0]) / 3.0,
        (v0[1] + v1[1] + v2[1]) / 3.0,
    );
}
