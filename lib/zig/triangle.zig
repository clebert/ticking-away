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

    /// SIMD: squared distance to all 3 edges
    pub fn edgeDistancesSq(self: Triangle, point: vec2.Vec2) @Vector(3, f32) {
        const px: @Vector(3, f32) = @splat(point[0]);
        const py: @Vector(3, f32) = @splat(point[1]);
        const zero: @Vector(3, f32) = @splat(0);
        const one: @Vector(3, f32) = @splat(1);

        const to_x = px - self.edge_start_x;
        const to_y = py - self.edge_start_y;
        const dot = to_x * self.edge_dir_x + to_y * self.edge_dir_y;
        const t = @min(@max(dot * self.edge_inv_len_sq, zero), one);

        const proj_x = self.edge_start_x + t * self.edge_dir_x;
        const proj_y = self.edge_start_y + t * self.edge_dir_y;
        const dx = px - proj_x;
        const dy = py - proj_y;

        return dx * dx + dy * dy;
    }

    /// SIMD 4-wide: 4 horizontal pixels × 3 edges
    pub fn edgeDistancesSq4(self: Triangle, px: @Vector(4, f32), py: @Vector(4, f32)) [3]@Vector(4, f32) {
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

    /// Creates isosceles triangle (prism) centered at point
    pub fn isosceles(center: vec2.Vec2, base_width: f32, apex_angle_deg: f32) Triangle {
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
