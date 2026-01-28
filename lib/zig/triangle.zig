const std = @import("std");

const range = @import("range.zig");
const vec2 = @import("vec2.zig");

pub const Triangle = struct {
    /// Edge data in SoA layout for SIMD (edges: 0→1, 1→2, 2→0)
    edge_start_x: @Vector(3, f32),
    edge_start_y: @Vector(3, f32),
    edge_dir_x: @Vector(3, f32),
    edge_dir_y: @Vector(3, f32),
    edge_inv_len_sq: @Vector(3, f32),

    /// Vertices sorted by y for scanline rasterization
    top: vec2.Vec2,
    mid: vec2.Vec2,
    bot: vec2.Vec2,
    mid_is_left: bool,

    pub fn init(v0: vec2.Vec2, v1: vec2.Vec2, v2: vec2.Vec2) Triangle {
        @setFloatMode(.optimized);
        // Sort vertices by y
        var sorted = [_]vec2.Vec2{ v0, v1, v2 };
        if (sorted[0][1] > sorted[1][1]) std.mem.swap(vec2.Vec2, &sorted[0], &sorted[1]);
        if (sorted[1][1] > sorted[2][1]) std.mem.swap(vec2.Vec2, &sorted[1], &sorted[2]);
        if (sorted[0][1] > sorted[1][1]) std.mem.swap(vec2.Vec2, &sorted[0], &sorted[1]);

        const top = sorted[0];
        const mid = sorted[1];
        const bot = sorted[2];

        const cross = (bot[0] - top[0]) * (mid[1] - top[1]) - (bot[1] - top[1]) * (mid[0] - top[0]);

        // Edge data (original vertex order for distance calc)
        const delta_x = @Vector(3, f32){ v1[0] - v0[0], v2[0] - v1[0], v0[0] - v2[0] };
        const delta_y = @Vector(3, f32){ v1[1] - v0[1], v2[1] - v1[1], v0[1] - v2[1] };
        const len_sq = delta_x * delta_x + delta_y * delta_y;
        const eps: @Vector(3, f32) = @splat(std.math.floatEps(f32));
        const one: @Vector(3, f32) = @splat(1.0);
        const zero: @Vector(3, f32) = @splat(0);

        return .{
            .edge_start_x = .{ v0[0], v1[0], v2[0] },
            .edge_start_y = .{ v0[1], v1[1], v2[1] },
            .edge_dir_x = delta_x,
            .edge_dir_y = delta_y,
            .edge_inv_len_sq = @select(f32, len_sq > eps, one / len_sq, zero),
            .top = top,
            .mid = mid,
            .bot = bot,
            .mid_is_left = cross > 0,
        };
    }

    /// Returns x-range for scanline at given y
    pub fn scanlineRange(self: Triangle, y: f32) ?range.Range {
        @setFloatMode(.optimized);
        if (y < self.top[1] or y > self.bot[1]) return null;

        const eps = std.math.floatEps(f32);
        const in_upper = y < self.mid[1];

        // Long edge (top→bot) always active
        const long_t = if (self.bot[1] - self.top[1] > eps)
            (y - self.top[1]) / (self.bot[1] - self.top[1])
        else
            0;
        const x_long = self.top[0] + long_t * (self.bot[0] - self.top[0]);

        // Short edge depends on which half
        const x_short = if (in_upper) blk: {
            const t = if (self.mid[1] - self.top[1] > eps)
                (y - self.top[1]) / (self.mid[1] - self.top[1])
            else
                0;
            break :blk self.top[0] + t * (self.mid[0] - self.top[0]);
        } else blk: {
            const t = if (self.bot[1] - self.mid[1] > eps)
                (y - self.mid[1]) / (self.bot[1] - self.mid[1])
            else
                0;
            break :blk self.mid[0] + t * (self.bot[0] - self.mid[0]);
        };

        return if (self.mid_is_left)
            range.Range{ .x_min = x_short, .x_max = x_long }
        else
            range.Range{ .x_min = x_long, .x_max = x_short };
    }

    /// SIMD 4-wide: 4 horizontal pixels × 3 edges
    pub fn edgeDistancesSq4(self: Triangle, px: @Vector(4, f32), py: @Vector(4, f32)) [3]@Vector(4, f32) {
        @setFloatMode(.optimized);
        var result: [3]@Vector(4, f32) = undefined;
        const zero: @Vector(4, f32) = @splat(0);
        const one: @Vector(4, f32) = @splat(1);

        inline for (0..3) |e| {
            const start_x: @Vector(4, f32) = @splat(self.edge_start_x[e]);
            const start_y: @Vector(4, f32) = @splat(self.edge_start_y[e]);
            const dir_x: @Vector(4, f32) = @splat(self.edge_dir_x[e]);
            const dir_y: @Vector(4, f32) = @splat(self.edge_dir_y[e]);
            const inv_len_sq: @Vector(4, f32) = @splat(self.edge_inv_len_sq[e]);

            const to_x = px - start_x;
            const to_y = py - start_y;
            const dot = to_x * dir_x + to_y * dir_y;
            const t = @min(@max(dot * inv_len_sq, zero), one);

            const proj_x = start_x + t * dir_x;
            const proj_y = start_y + t * dir_y;
            const dx = px - proj_x;
            const dy = py - proj_y;

            result[e] = dx * dx + dy * dy;
        }
        return result;
    }

    pub fn minY(self: Triangle) f32 {
        return self.top[1];
    }

    pub fn maxY(self: Triangle) f32 {
        return self.bot[1];
    }

    pub fn getVertex(self: Triangle, index: u2) vec2.Vec2 {
        return vec2.xy(self.edge_start_x[index], self.edge_start_y[index]);
    }

    pub const Edge = struct {
        start: vec2.Vec2,
        end: vec2.Vec2,
    };

    pub fn getEdge(self: Triangle, index: u2) Edge {
        const next = (index + 1) % 3;
        return .{
            .start = vec2.xy(self.edge_start_x[index], self.edge_start_y[index]),
            .end = vec2.xy(self.edge_start_x[next], self.edge_start_y[next]),
        };
    }

    pub fn centroid(self: Triangle) vec2.Vec2 {
        @setFloatMode(.optimized);
        const x = (self.edge_start_x[0] + self.edge_start_x[1] + self.edge_start_x[2]) / 3.0;
        const y = (self.edge_start_y[0] + self.edge_start_y[1] + self.edge_start_y[2]) / 3.0;
        return vec2.xy(x, y);
    }

    /// Creates isosceles triangle (prism) centered at point
    pub fn isosceles(center: vec2.Vec2, base_width: f32, apex_angle_deg: f32) Triangle {
        @setFloatMode(.optimized);
        const angle = std.math.clamp(apex_angle_deg, 1.0, 179.0);
        const half_rad = angle / 2.0 * std.math.pi / 180.0;
        const h = (base_width / 2.0) / @tan(half_rad);

        const apex_offset = 2.0 * h / 3.0;
        const base_offset = h / 3.0;

        return Triangle.init(
            vec2.xy(center[0], center[1] - apex_offset),
            vec2.xy(center[0] + base_width / 2.0, center[1] + base_offset),
            vec2.xy(center[0] - base_width / 2.0, center[1] + base_offset),
        );
    }

    /// SIMD 4-wide: test if 4 points are inside triangle
    pub fn containsPoint4(self: Triangle, px: @Vector(4, f32), py: @Vector(4, f32)) @Vector(4, bool) {
        @setFloatMode(.optimized);
        const v0 = self.top;
        const v1 = self.mid;
        const v2 = self.bot;

        // Precompute constants (same for all 4 points)
        const edge1 = v1 - v0;
        const edge2 = v2 - v0;
        const d00 = vec2.dot(edge1, edge1);
        const d01 = vec2.dot(edge1, edge2);
        const d11 = vec2.dot(edge2, edge2);
        const denom = d00 * d11 - d01 * d01;

        // Degenerate triangle (collinear points)
        if (@abs(denom) < std.math.floatEps(f32)) return @splat(false);

        const inv_denom = 1.0 / denom;

        // Vectorized point-relative computation
        const v0x: @Vector(4, f32) = @splat(v0[0]);
        const v0y: @Vector(4, f32) = @splat(v0[1]);
        const px_rel = px - v0x;
        const py_rel = py - v0y;

        // d20 = dot(p - v0, edge1) for each point
        const e1x: @Vector(4, f32) = @splat(edge1[0]);
        const e1y: @Vector(4, f32) = @splat(edge1[1]);
        const d20 = px_rel * e1x + py_rel * e1y;

        // d21 = dot(p - v0, edge2) for each point
        const e2x: @Vector(4, f32) = @splat(edge2[0]);
        const e2y: @Vector(4, f32) = @splat(edge2[1]);
        const d21 = px_rel * e2x + py_rel * e2y;

        // Barycentric coordinates
        const d11_vec: @Vector(4, f32) = @splat(d11);
        const d01_vec: @Vector(4, f32) = @splat(d01);
        const d00_vec: @Vector(4, f32) = @splat(d00);
        const inv_denom_vec: @Vector(4, f32) = @splat(inv_denom);

        const u = (d11_vec * d20 - d01_vec * d21) * inv_denom_vec;
        const v = (d00_vec * d21 - d01_vec * d20) * inv_denom_vec;

        const zero: @Vector(4, f32) = @splat(0);
        const one: @Vector(4, f32) = @splat(1);
        return (u >= zero) & (v >= zero) & ((u + v) <= one);
    }
};
