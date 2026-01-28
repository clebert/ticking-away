# Prism Glow Implementation Plan

Minimal, SIMD-optimized implementation using scanline rasterization.

## Design Principles

1. **Scanline-based** - band rendering is scanline-based, so bounds computation fits naturally
2. **No wasted pixels** - exact x-bounds per y, no brute-force iteration
3. **Cache-friendly** - horizontal pixels are contiguous in memory
4. **SIMD 4-wide** - process 4 consecutive x pixels with `@Vector(4, f32)`

Even on non-SIMD hardware, the 4-wide loop benefits from:

- Cache line efficiency (4 RGBA pixels = 64 bytes = 1 cache line)
- Loop unrolling reduces branch overhead
- Instruction-level parallelism in scalar pipelines

---

## Phase 1: Triangle & Prism Glow

New feature: inner glow on triangle edges.

### 1.1 Create `lib/zig/range.zig`

Shared type for scanline x-ranges used throughout the codebase:

```zig
/// X-range for scanline intersection results
pub const Range = struct {
    x_min: f32,
    x_max: f32,

    pub fn intersect(self: Range, other: Range) ?Range {
        const result = Range{
            .x_min = @max(self.x_min, other.x_min),
            .x_max = @min(self.x_max, other.x_max),
        };
        return if (result.x_min <= result.x_max) result else null;
    }
};
```

### 1.2 Create `lib/zig/triangle.zig`

```zig
const std = @import("std");
const Range = @import("range.zig").Range;
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
    pub fn scanlineRange(self: Triangle, y: f32) ?Range {
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
            Range{ .x_min = x_short, .x_max = x_long }
        else
            Range{ .x_min = x_long, .x_max = x_short };
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
};

/// Creates isoceles triangle (prism) centered at point
pub fn isoceles(center: vec2.Vec2, base_width: f32, apex_angle_deg: f32) Triangle {
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
```

### 1.3 Add `renderPrismGlow` to `lib/zig/band.zig`

```zig
const triangle = @import("triangle.zig");

fn smoothMin(a: f32, b: f32, k: f32) f32 {
    const h = @max(k - @abs(a - b), 0) / k;
    return @min(a, b) - h * h * k * 0.25;
}

fn smoothMin4(a: @Vector(4, f32), b: @Vector(4, f32), k: @Vector(4, f32)) @Vector(4, f32) {
    const zero: @Vector(4, f32) = @splat(0);
    const quarter: @Vector(4, f32) = @splat(0.25);
    const h = @max(k - @abs(a - b), zero) / k;
    return @min(a, b) - h * h * k * quarter;
}

pub fn renderPrismGlow(
    self: *Context,
    tri: triangle.Triangle,
    glow_color: color.Color,
    glow_width: f32,
    intensity: f32,
    falloff: glow.Falloff,
) void {
    const smooth_k = glow_width * 0.5;

    const y_min = @max(self.y_offset, @as(usize, @intFromFloat(@max(0, tri.minY()))));
    const y_max = @min(self.y_offset + self.height, @as(usize, @intFromFloat(tri.maxY())) + 1);

    for (y_min..y_max) |global_y| {
        const local_y = global_y - self.y_offset;
        const y_f: f32 = @floatFromInt(global_y);

        const range = tri.scanlineRange(y_f + 0.5) orelse continue;
        const x_start = @max(0, @as(usize, @intFromFloat(range.x_min)));
        const x_end = @min(self.width, @as(usize, @intFromFloat(range.x_max)) + 1);

        var x = x_start;
        const py: @Vector(4, f32) = @splat(y_f + 0.5);
        const glow_width_vec: @Vector(4, f32) = @splat(glow_width);
        const smooth_k_vec: @Vector(4, f32) = @splat(smooth_k);

        while (x + 4 <= x_end) : (x += 4) {
            const base: @Vector(4, f32) = @splat(@floatFromInt(x));
            const px = base + @Vector(4, f32){ 0.5, 1.5, 2.5, 3.5 };
            const dist_sq = tri.edgeDistancesSq4(px, py);

            // Vectorized sqrt for all 3 edges × 4 pixels
            const d0 = @sqrt(dist_sq[0]);
            const d1 = @sqrt(dist_sq[1]);
            const d2 = @sqrt(dist_sq[2]);

            // Vectorized smoothMin
            const dist = smoothMin4(smoothMin4(d0, d1, smooth_k_vec), d2, smooth_k_vec);

            // Early exit if all 4 pixels are outside glow radius
            const mask = dist < glow_width_vec;
            if (!@reduce(.Or, mask)) continue;

            const t = dist / glow_width_vec;

            inline for (0..4) |i| {
                if (!mask[i]) continue;
                const alpha = falloff.apply(t[i]) * intensity;
                self.pixel(x + i, local_y).* += @as(color.Color, @splat(alpha)) * glow_color;
            }
        }

        while (x < x_end) : (x += 1) {
            const point = vec2.xy(@as(f32, @floatFromInt(x)) + 0.5, y_f + 0.5);
            const dist_sq = tri.edgeDistancesSq(point);
            const d0 = @sqrt(dist_sq[0]);
            const d1 = @sqrt(dist_sq[1]);
            const d2 = @sqrt(dist_sq[2]);
            const dist = smoothMin(smoothMin(d0, d1, smooth_k), d2, smooth_k);

            if (dist < glow_width) {
                const t = dist / glow_width;
                const alpha = falloff.apply(t) * intensity;
                self.pixel(x, local_y).* += @as(color.Color, @splat(alpha)) * glow_color;
            }
        }
    }
}
```

### 1.4 Update `lib/zig/root.zig`

```zig
pub const range = @import("range.zig");
pub const triangle = @import("triangle.zig");
```

### Phase 1 Checklist

- [ ] Create `lib/zig/range.zig` with shared `Range` type
- [ ] Create `lib/zig/triangle.zig`
- [ ] Add `renderPrismGlow()` to `band.zig`
- [ ] Update `root.zig` exports
- [ ] Add tests
- [ ] Run `npm run ci`
- [ ] Visual comparison with C implementation

---

## Phase 2: Scanline Clipping Interface

Separation of concerns for geometric clipping. `renderGlowLine` should not know about arbitrary
shapes—it only intersects x-ranges.

### Design

**Why tagged union over function pointers:**

- Switch statements inline and optimize; function pointers prevent this
- No indirection overhead
- LLVM can optimize across the switch boundary
- Scanline range computed once per row (O(height)), SIMD operates inside the range (O(width))

**Exclusion requires per-pixel testing:**

- Exclusion creates disjoint ranges (e.g., circle minus triangle = two segments)
- Only used for entry/exit rays (glow bleeding past prism edge)
- Acceptable cost: per-pixel `point_in_triangle` only when `exclude` is non-null

### 2.1 Create `lib/zig/clip.zig`

```zig
const Range = @import("range.zig").Range;
const triangle = @import("triangle.zig");
const circle = @import("circle.zig");

pub const ScanlineClip = union(enum) {
    triangle: *const triangle.Triangle,
    circle: *const circle.Circle,

    pub fn scanlineRange(self: ScanlineClip, y: f32) ?Range {
        return switch (self) {
            .triangle => |t| t.scanlineRange(y),
            .circle => |c| c.scanlineRange(y),
        };
    }
};
```

### 2.2 Create `lib/zig/circle.zig`

```zig
const Range = @import("range.zig").Range;
const vec2 = @import("vec2.zig");

pub const Circle = struct {
    center: vec2.Vec2,
    radius: f32,

    pub fn init(center: vec2.Vec2, radius: f32) Circle {
        return .{ .center = center, .radius = radius };
    }

    /// Returns x-range where scanline y intersects circle
    pub fn scanlineRange(self: Circle, y: f32) ?Range {
        const dy = y - self.center[1];
        if (@abs(dy) > self.radius) return null;
        const dx = @sqrt(self.radius * self.radius - dy * dy);
        return Range{
            .x_min = self.center[0] - dx,
            .x_max = self.center[0] + dx,
        };
    }
};
```

### 2.3 Update `renderGlowLine` in `lib/zig/band.zig`

```zig
const clip = @import("clip.zig");
const Range = @import("range.zig").Range;
const triangle = @import("triangle.zig");

pub fn renderGlowLine(
    self: *Context,
    segment: line.Segment,
    config: glow.Config,
    maybe_clip: ?clip.ScanlineClip,
    exclude: ?*const triangle.Triangle,
) void {
    const glow_width = config.width;
    const glow_width_sq = glow_width * glow_width;

    for (0..self.height) |local_y| {
        const global_y = self.globalY(local_y);
        const y_f: f32 = @floatFromInt(global_y);
        const y_center = y_f + 0.5;

        // Capsule bounds for this scanline
        const capsule_range = segment.capsuleScanlineRange(y_center, glow_width) orelse continue;

        // Intersect with clip if provided
        const range = if (maybe_clip) |c| blk: {
            const clip_range = c.scanlineRange(y_center) orelse continue;
            break :blk capsule_range.intersect(clip_range) orelse continue;
        } else capsule_range;

        const x_start: usize = @intFromFloat(@max(0, range.x_min));
        const x_end: usize = @min(self.width, @as(usize, @intFromFloat(range.x_max)) + 1);

        // SIMD loop: 4 pixels at a time
        var x = x_start;
        const py: @Vector(4, f32) = @splat(y_center);
        const glow_width_sq_vec: @Vector(4, f32) = @splat(glow_width_sq);
        const glow_width_vec: @Vector(4, f32) = @splat(glow_width);

        while (x + 4 <= x_end) : (x += 4) {
            const base: @Vector(4, f32) = @splat(@floatFromInt(x));
            const px = base + @Vector(4, f32){ 0.5, 1.5, 2.5, 3.5 };
            const result = segment.distanceSq4(px, py);

            // Early exit if all 4 pixels are outside glow radius
            const mask = result.distance_sq < glow_width_sq_vec;
            if (!@reduce(.Or, mask)) continue;

            // Vectorized sqrt and division
            const distances = @sqrt(result.distance_sq);
            const radial_t = distances / glow_width_vec;

            inline for (0..4) |i| {
                if (!mask[i]) continue;

                // Per-pixel exclusion test (only when exclude is set)
                if (exclude) |tri| {
                    const point = vec2.xy(px[i], y_center);
                    if (tri.containsPoint(point)) continue;
                }

                const intensity = config.falloff.apply(radial_t[i]);

                const base_color = switch (config.color) {
                    .uniform => |c| c,
                    .gradient => |g| color.lerp(g.start, g.end, result.t[i]),
                };

                self.pixel(x + i, local_y).* += @as(color.Color, @splat(intensity)) * base_color;
            }
        }

        // Scalar tail
        while (x < x_end) : (x += 1) {
            const point = vec2.xy(@as(f32, @floatFromInt(x)) + 0.5, y_center);

            if (exclude) |tri| {
                if (tri.containsPoint(point)) continue;
            }

            const result = segment.distanceSq(point);
            if (result.distance_sq >= glow_width_sq) continue;

            const distance = @sqrt(result.distance_sq);
            const radial_t = distance / glow_width;
            const intensity = config.falloff.apply(radial_t);

            const base_color = switch (config.color) {
                .uniform => |c| c,
                .gradient => |g| color.lerp(g.start, g.end, result.t),
            };

            self.pixel(x, local_y).* += @as(color.Color, @splat(intensity)) * base_color;
        }
    }
}
```

### 2.4 Add `Triangle.containsPoint` to `lib/zig/triangle.zig`

```zig
/// Returns true if point is inside the triangle (for exclusion tests)
pub fn containsPoint(self: Triangle, point: vec2.Vec2) bool {
    // Use barycentric coordinates or edge function
    // Reuse sorted vertices: top, mid, bot
    const v0 = self.top;
    const v1 = self.mid;
    const v2 = self.bot;

    const d00 = vec2.dot(v1 - v0, v1 - v0);
    const d01 = vec2.dot(v1 - v0, v2 - v0);
    const d11 = vec2.dot(v2 - v0, v2 - v0);
    const d20 = vec2.dot(point - v0, v1 - v0);
    const d21 = vec2.dot(point - v0, v2 - v0);

    const denom = d00 * d11 - d01 * d01;
    if (@abs(denom) < std.math.floatEps(f32)) return false;

    const inv_denom = 1.0 / denom;
    const u = (d11 * d20 - d01 * d21) * inv_denom;
    const v = (d00 * d21 - d01 * d20) * inv_denom;

    return u >= 0 and v >= 0 and (u + v) <= 1;
}
```

### 2.5 Update `lib/zig/root.zig`

```zig
pub const clip = @import("clip.zig");
pub const circle = @import("circle.zig");
```

### Phase 2 Checklist

- [ ] Create `lib/zig/clip.zig` with `ScanlineClip` union
- [ ] Create `lib/zig/circle.zig` with `Circle` struct and `scanlineRange`
- [ ] Add `Triangle.containsPoint` for exclusion tests
- [ ] Update `renderGlowLine` to use `ScanlineClip`, `Range.intersect`, and optional exclusion
- [ ] Update `root.zig` exports to include `clip` and `circle`
- [ ] Update all call sites
- [ ] Run `npm run ci`
