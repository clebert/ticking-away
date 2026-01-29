const std = @import("std");

const range = @import("../math/range.zig");
const vec2 = @import("../math/vec2.zig");

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

pub const Prism = struct {
    vertices_x: @Vector(3, f32),
    vertices_y: @Vector(3, f32),

    pub fn getVertex(self: Prism, vertex: Vertex) vec2.Vec2 {
        const index = @intFromEnum(vertex);

        return vec2.xy(self.vertices_x[index], self.vertices_y[index]);
    }

    pub fn scanlineRange(self: Prism, y: f32) ?range.Range {
        @setFloatMode(.optimized);

        const t = self.getVertex(.apex);
        const m = self.getVertex(.bottom_left);
        const b = self.getVertex(.bottom_right);

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

    pub fn containsPoint(self: Prism, px: f32, py: f32) bool {
        @setFloatMode(.optimized);
        // Use original vertex order (not sorted) for consistent winding
        const x0 = self.vertices_x[0];
        const y0 = self.vertices_y[0];
        const x1 = self.vertices_x[1];
        const y1 = self.vertices_y[1];
        const x2 = self.vertices_x[2];
        const y2 = self.vertices_y[2];

        // Simple barycentric test (matches C implementation)
        const denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
        if (@abs(denom) < 1e-9) return false;

        const inv_denom = 1.0 / denom;
        const a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) * inv_denom;
        const b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) * inv_denom;

        return (a >= 0) and (b >= 0) and ((a + b) <= 1);
    }

    pub fn minY(self: Prism) f32 {
        return self.vertices_y[0];
    }

    pub fn maxY(self: Prism) f32 {
        return self.vertices_y[1];
    }

    pub fn smoothEdgeDistance(self: Prism, point: vec2.Vec2, k: f32) f32 {
        @setFloatMode(.optimized);
        const d0 = @sqrt(self.getEdge(.right).distanceSq(point));
        const d1 = @sqrt(self.getEdge(.bottom).distanceSq(point));
        const d2 = @sqrt(self.getEdge(.left).distanceSq(point));
        return smoothMin(smoothMin(d0, d1, k), d2, k);
    }

    pub const EdgeSegment = struct {
        start: vec2.Vec2,
        end: vec2.Vec2,

        pub fn distanceSq(self: EdgeSegment, point: vec2.Vec2) f32 {
            @setFloatMode(.optimized);
            const dir = self.end - self.start;
            const len_sq = vec2.dot(dir, dir);

            if (len_sq < 1e-9) {
                const delta = point - self.start;
                return vec2.dot(delta, delta);
            }

            const to_point = point - self.start;
            const t = @min(@max(vec2.dot(to_point, dir) / len_sq, 0), 1);
            const proj = self.start + @as(vec2.Vec2, @splat(t)) * dir;
            const delta = point - proj;

            return vec2.dot(delta, delta);
        }
    };

    pub fn getEdge(self: Prism, edge: Edge) EdgeSegment {
        return .{
            .start = self.getVertex(edge.startVertex()),
            .end = self.getVertex(edge.endVertex()),
        };
    }

    pub fn centroid(self: Prism) vec2.Vec2 {
        @setFloatMode(.optimized);
        const v0 = self.getVertex(.apex);
        const v1 = self.getVertex(.bottom_right);
        const v2 = self.getVertex(.bottom_left);
        return vec2.xy(
            (v0[0] + v1[0] + v2[0]) / 3.0,
            (v0[1] + v1[1] + v2[1]) / 3.0,
        );
    }
    pub fn equilateral(center: vec2.Vec2, base_width: f32) Prism {
        @setFloatMode(.optimized);
        const sqrt3 = @sqrt(3.0);
        const half_base = base_width / 2.0;

        const apex_offset = base_width * sqrt3 / 3.0;
        const base_offset = base_width * sqrt3 / 6.0;

        // v0 = apex (top), v1 = bottom-right, v2 = bottom-left
        const v0 = vec2.xy(center[0], center[1] - apex_offset);
        const v1 = vec2.xy(center[0] + half_base, center[1] + base_offset);
        const v2 = vec2.xy(center[0] - half_base, center[1] + base_offset);

        return .{
            .vertices_x = .{ v0[0], v1[0], v2[0] },
            .vertices_y = .{ v0[1], v1[1], v2[1] },
        };
    }
};

fn smoothMin(a: f32, b: f32, k: f32) f32 {
    @setFloatMode(.optimized);
    const h = @max(k - @abs(a - b), 0) / k;
    return @min(a, b) - h * h * k * 0.25;
}
