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
