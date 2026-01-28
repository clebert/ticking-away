const std = @import("std");

const range = @import("range.zig");
const vec2 = @import("vec2.zig");

pub const Triangle = struct {
    // Edge data in SoA layout for SIMD (edges: 0→1, 1→2, 2→0)
    edge_start_x: @Vector(3, f32),
    edge_start_y: @Vector(3, f32),
    edge_dir_x: @Vector(3, f32),
    edge_dir_y: @Vector(3, f32),
    edge_inv_len_sq: @Vector(3, f32),

    // Vertices sorted by y for scanline rasterization
    top: vec2.Vec2,
    mid: vec2.Vec2,
    bot: vec2.Vec2,
    mid_is_left: bool,

    pub fn init(v0: vec2.Vec2, v1: vec2.Vec2, v2: vec2.Vec2) Triangle {
        @setFloatMode(.optimized);
        var sorted = [_]vec2.Vec2{ v0, v1, v2 };
        if (sorted[0][1] > sorted[1][1]) std.mem.swap(vec2.Vec2, &sorted[0], &sorted[1]);
        if (sorted[1][1] > sorted[2][1]) std.mem.swap(vec2.Vec2, &sorted[1], &sorted[2]);
        if (sorted[0][1] > sorted[1][1]) std.mem.swap(vec2.Vec2, &sorted[0], &sorted[1]);

        const top = sorted[0];
        const mid = sorted[1];
        const bot = sorted[2];
        // Cross product > 0 means mid is to the left of line from top to bot
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

    pub fn getVertex(self: Triangle, index: u2) vec2.Vec2 {
        return vec2.xy(self.edge_start_x[index], self.edge_start_y[index]);
    }

    pub fn scanlineRange(self: Triangle, y: f32) ?range.Range {
        @setFloatMode(.optimized);
        if (y < self.top[1] or y > self.bot[1]) return null;

        const eps = std.math.floatEps(f32);
        const in_upper = y < self.mid[1];

        const long_t = if (self.bot[1] - self.top[1] > eps)
            (y - self.top[1]) / (self.bot[1] - self.top[1])
        else
            0;
        const x_long = self.top[0] + long_t * (self.bot[0] - self.top[0]);

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

    pub fn containsPoint(self: Triangle, px: f32, py: f32) bool {
        @setFloatMode(.optimized);
        // Use original vertex order (not sorted) for consistent winding
        const x0 = self.edge_start_x[0];
        const y0 = self.edge_start_y[0];
        const x1 = self.edge_start_x[1];
        const y1 = self.edge_start_y[1];
        const x2 = self.edge_start_x[2];
        const y2 = self.edge_start_y[2];

        // Simple barycentric test (matches C implementation)
        const denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
        if (@abs(denom) < 1e-9) return false;

        const inv_denom = 1.0 / denom;
        const a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) * inv_denom;
        const b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) * inv_denom;

        return (a >= 0) and (b >= 0) and ((a + b) <= 1);
    }

    pub fn minEdgeDistanceSq(self: Triangle, px: f32, py: f32) f32 {
        @setFloatMode(.optimized);
        // SIMD distance calculation for all 3 edges
        const px_vec: @Vector(3, f32) = @splat(px);
        const py_vec: @Vector(3, f32) = @splat(py);

        const to_x = px_vec - self.edge_start_x;
        const to_y = py_vec - self.edge_start_y;

        const dot_val = to_x * self.edge_dir_x + to_y * self.edge_dir_y;
        const zero: @Vector(3, f32) = @splat(0);
        const one: @Vector(3, f32) = @splat(1);
        const t = @min(@max(dot_val * self.edge_inv_len_sq, zero), one);

        const proj_x = self.edge_start_x + t * self.edge_dir_x;
        const proj_y = self.edge_start_y + t * self.edge_dir_y;
        const dx = px_vec - proj_x;
        const dy = py_vec - proj_y;
        const dist_sq = dx * dx + dy * dy;

        return @min(dist_sq[0], @min(dist_sq[1], dist_sq[2]));
    }

    pub fn minY(self: Triangle) f32 {
        return self.top[1];
    }

    pub fn maxY(self: Triangle) f32 {
        return self.bot[1];
    }

    pub const Edge = struct {
        start: vec2.Vec2,
        end: vec2.Vec2,
    };

    pub fn getEdge(self: Triangle, index: u2) Edge {
        const start = self.getVertex(index);
        const next_index: u2 = @intCast((@as(u3, index) + 1) % 3);
        const end = self.getVertex(next_index);
        return .{ .start = start, .end = end };
    }

    pub fn centroid(self: Triangle) vec2.Vec2 {
        @setFloatMode(.optimized);
        const v0 = self.getVertex(0);
        const v1 = self.getVertex(1);
        const v2 = self.getVertex(2);
        return vec2.xy(
            (v0[0] + v1[0] + v2[0]) / 3.0,
            (v0[1] + v1[1] + v2[1]) / 3.0,
        );
    }

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
};
