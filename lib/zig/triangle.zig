const std = @import("std");

const range = @import("range.zig");
const vec2 = @import("vec2.zig");

pub const Vertex = enum(u2) {
    apex = 0,
    bottom_right = 1,
    bottom_left = 2,

    /// Returns the edge opposite to this vertex (doesn't touch this vertex).
    pub fn oppositeEdge(self: Vertex) Edge {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }
};

pub const Edge = enum(u2) {
    right = 0, // apex -> bottom_right
    bottom = 1, // bottom_right -> bottom_left
    left = 2, // bottom_left -> apex

    /// Returns the vertex at the start of this edge.
    pub fn startVertex(self: Edge) Vertex {
        return @enumFromInt(@intFromEnum(self));
    }

    /// Returns the vertex at the end of this edge.
    pub fn endVertex(self: Edge) Vertex {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) % 3);
    }

    /// Returns the vertex opposite to this edge (not an endpoint of this edge).
    pub fn oppositeVertex(self: Edge) Vertex {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 2) % 3);
    }

    /// Returns true if the given vertex is an endpoint of this edge.
    pub fn touchesVertex(self: Edge, vertex: Vertex) bool {
        return vertex == self.startVertex() or vertex == self.endVertex();
    }
};

pub const Triangle = struct {
    vertices_x: @Vector(3, f32),
    vertices_y: @Vector(3, f32),

    pub fn getVertex(self: Triangle, vertex: Vertex) vec2.Vec2 {
        const index = @intFromEnum(vertex);
        return vec2.xy(self.vertices_x[index], self.vertices_y[index]);
    }

    // Scanline rasterization accessors (equilateral: top=apex, mid=left, bot=right)
    inline fn top(self: Triangle) vec2.Vec2 {
        return self.getVertex(.apex);
    }
    inline fn mid(self: Triangle) vec2.Vec2 {
        return self.getVertex(.bottom_left);
    }
    inline fn bot(self: Triangle) vec2.Vec2 {
        return self.getVertex(.bottom_right);
    }

    // band.zig Context.renderPrismGlow
    // clip.zig Region.scanlineRange
    pub fn scanlineRange(self: Triangle, y: f32) ?range.Range {
        @setFloatMode(.optimized);
        const t = self.top();
        const m = self.mid();
        const b = self.bot();

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

    // band.zig Context.renderGlowLine
    // band.zig Context.renderGradient
    // grain.zig apply
    pub fn containsPoint(self: Triangle, px: f32, py: f32) bool {
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

    // band.zig renderPrismGlow
    pub fn minY(self: Triangle) f32 {
        return self.vertices_y[0];
    }

    // band.zig renderPrismGlow
    pub fn maxY(self: Triangle) f32 {
        return self.vertices_y[1];
    }

    pub const EdgeSegment = struct {
        start: vec2.Vec2,
        end: vec2.Vec2,
    };

    // intersect.zig rayTriangleEntry
    // intersect.zig rayTriangleExit
    // intersect.zig triangleScale
    pub fn getEdge(self: Triangle, edge: Edge) EdgeSegment {
        return .{
            .start = self.getVertex(edge.startVertex()),
            .end = self.getVertex(edge.endVertex()),
        };
    }

    // spectrum.zig Paths.compute
    pub fn centroid(self: Triangle) vec2.Vec2 {
        @setFloatMode(.optimized);
        const v0 = self.getVertex(.apex);
        const v1 = self.getVertex(.bottom_right);
        const v2 = self.getVertex(.bottom_left);
        return vec2.xy(
            (v0[0] + v1[0] + v2[0]) / 3.0,
            (v0[1] + v1[1] + v2[1]) / 3.0,
        );
    }

    // scene.zig Scene.updatePrism
    // Creates an equilateral triangle (60°/60°/60°) centered at the given point.
    // For equilateral: h = base * √3/2, apex_offset = base * √3/3, base_offset = base * √3/6
    pub fn equilateral(center: vec2.Vec2, base_width: f32) Triangle {
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
