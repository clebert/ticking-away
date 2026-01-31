const std = @import("std");

const scanline = @import("../rendering/scanline.zig");
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

pub const Prism = struct {
    vertices: std.EnumArray(Vertex, vec2.Vec2),

    pub fn scanlineRange(self: Prism, y: f32) ?scanline.Range {
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

    pub fn containsPoint(self: Prism, px: f32, py: f32) bool {
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

    pub fn minY(self: Prism) f32 {
        return self.vertices.get(.apex)[1];
    }

    pub fn maxY(self: Prism) f32 {
        return self.vertices.get(.bottom_right)[1];
    }

    pub const EdgeSegment = struct {
        start: vec2.Vec2,
        end: vec2.Vec2,

        pub fn distanceSq(self: EdgeSegment, point: vec2.Vec2) f32 {
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
            .start = self.vertices.get(edge.startVertex()),
            .end = self.vertices.get(edge.endVertex()),
        };
    }

    pub fn centroid(self: Prism) vec2.Vec2 {
        const v0 = self.vertices.get(.apex);
        const v1 = self.vertices.get(.bottom_right);
        const v2 = self.vertices.get(.bottom_left);
        return vec2.xy(
            (v0[0] + v1[0] + v2[0]) / 3.0,
            (v0[1] + v1[1] + v2[1]) / 3.0,
        );
    }
    pub fn init(center: vec2.Vec2, base_width: f32) Prism {
        const sqrt3 = @sqrt(3.0);
        const half_base = base_width / 2.0;

        const apex_offset = base_width * sqrt3 / 3.0;
        const base_offset = base_width * sqrt3 / 6.0;

        // v0 = apex (top), v1 = bottom-right, v2 = bottom-left
        const v0 = vec2.xy(center[0], center[1] - apex_offset);
        const v1 = vec2.xy(center[0] + half_base, center[1] + base_offset);
        const v2 = vec2.xy(center[0] - half_base, center[1] + base_offset);

        return .{
            .vertices = std.EnumArray(Vertex, vec2.Vec2).init(.{
                .apex = v0,
                .bottom_right = v1,
                .bottom_left = v2,
            }),
        };
    }
};
