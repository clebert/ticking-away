const std = @import("std");
const testing = std.testing;

const color = @import("../color/color.zig");
const prism = @import("../geometry/prism.zig");
const segment = @import("../geometry/segment.zig");
const vec2 = @import("../math/vec2.zig");
const band = @import("band.zig");
const clip = @import("clip.zig");

pub const Falloff = enum {
    linear,
    quadratic,
    cubic,
    exponential,

    pub fn apply(self: Falloff, t: f32) f32 {
        std.debug.assert(t >= 0);
        std.debug.assert(t <= 1);

        const one_minus_t = 1 - t;

        return switch (self) {
            .linear => one_minus_t,
            .quadratic => one_minus_t * one_minus_t,
            .cubic => one_minus_t * one_minus_t * one_minus_t,
            .exponential => @exp(-3 * t) * one_minus_t,
        };
    }
};

pub const Config = struct {
    width: f32,
    falloff: Falloff = .quadratic,

    color: union(enum) {
        uniform: color.Color,
        gradient: struct { start: color.Color, end: color.Color },
    } = .{ .uniform = color.white },

    /// Intensity along the line (start to end). Used for fade-out effects.
    intensity: union(enum) {
        uniform: f32,
        gradient: struct { start: f32, end: f32 },
    } = .{ .uniform = 1.0 },
};

fn smoothPrismDistance(p: *const prism.Prism, point: vec2.Vec2, k: f32) f32 {
    const d0 = @sqrt(p.getEdge(.right).distanceSq(point));
    const d1 = @sqrt(p.getEdge(.bottom).distanceSq(point));
    const d2 = @sqrt(p.getEdge(.left).distanceSq(point));
    return smoothMin(smoothMin(d0, d1, k), d2, k);
}

fn smoothMin(a: f32, b: f32, k: f32) f32 {
    const h = @max(k - @abs(a - b), 0) / k;
    return @min(a, b) - h * h * k * 0.25;
}

pub fn renderLine(
    ctx: *band.Context,
    seg: segment.Segment,
    config: Config,
    clip_to: ?clip.Region,
    exclude: ?*const prism.Prism,
) void {
    const glow_width = config.width;
    const glow_width_sq = glow_width * glow_width;

    const bounds = seg.boundingBox(glow_width);
    const y_min = @max(0, @as(isize, @intFromFloat(bounds.min[1])));
    const y_max = @min(@as(isize, @intCast(ctx.total_height)), @as(isize, @intFromFloat(bounds.max[1])) + 1);
    const x_min = @max(0, @as(isize, @intFromFloat(bounds.min[0])));
    const x_max = @min(@as(isize, @intCast(ctx.width)), @as(isize, @intFromFloat(bounds.max[0])) + 1);

    if (y_min >= y_max or x_min >= x_max) return;

    const x_start: usize = @intCast(x_min);
    const x_end: usize = @intCast(x_max);

    const band_y_min: isize = @intCast(ctx.y_offset);
    const band_y_max: isize = @intCast(ctx.y_offset + ctx.height);

    if (y_max <= band_y_min or y_min >= band_y_max) return;

    const local_y_start: usize = if (y_min < band_y_min) 0 else @intCast(y_min - band_y_min);
    const local_y_end: usize = if (y_max > band_y_max) ctx.height else @intCast(y_max - band_y_min);

    for (local_y_start..local_y_end) |local_y| {
        const global_y = ctx.y_offset + local_y;
        const y_f: f32 = @floatFromInt(global_y);
        const y_center = y_f + 0.5;

        var row_x_start = x_start;
        var row_x_end = x_end;
        if (clip_to) |region| {
            const clip_range = region.scanlineRange(y_center) orelse continue;
            row_x_start = @max(row_x_start, @as(usize, @intFromFloat(@max(0, clip_range.x_min))));
            row_x_end = @min(row_x_end, @as(usize, @intFromFloat(clip_range.x_max)) + 1);
            if (row_x_start >= row_x_end) continue;
        }

        for (row_x_start..row_x_end) |x| {
            const px = @as(f32, @floatFromInt(x)) + 0.5;

            if (exclude) |tri| {
                if (tri.containsPoint(px, y_center)) continue;
            }

            const result = seg.distanceSq(px, y_center);
            if (result.distance_sq >= glow_width_sq) continue;

            const distance = @sqrt(result.distance_sq);
            const radial_t = distance / glow_width;
            const radial_intensity = config.falloff.apply(radial_t);
            const linear_intensity = switch (config.intensity) {
                .uniform => |v| v,
                .gradient => |g| g.start + (g.end - g.start) * result.t,
            };
            const intensity = radial_intensity * linear_intensity;
            const base_color = switch (config.color) {
                .uniform => |c| c,
                .gradient => |g| color.lerp(g.start, g.end, result.t),
            };

            const p = &ctx.buffer[local_y * ctx.width + x];
            const scale_vec: color.Color = @splat(intensity);
            p.* = p.* + base_color * scale_vec;
        }
    }
}

pub fn renderPrismEdges(
    ctx: *band.Context,
    tri: prism.Prism,
    glow_color: color.Color,
    glow_width: f32,
    intensity: f32,
    falloff: Falloff,
) void {
    const smooth_k = glow_width * 0.5;

    const y_min = @max(ctx.y_offset, @as(usize, @intFromFloat(@max(0, tri.minY()))));
    const y_max = @min(ctx.y_offset + ctx.height, @as(usize, @intFromFloat(tri.maxY())) + 1);

    for (y_min..y_max) |global_y| {
        const local_y = global_y - ctx.y_offset;
        const y_f: f32 = @floatFromInt(global_y);
        const y_center = y_f + 0.5;

        const tri_range = tri.scanlineRange(y_center) orelse continue;
        const x_start = @max(0, @as(usize, @intFromFloat(tri_range.x_min)));
        const x_end = @min(ctx.width, @as(usize, @intFromFloat(tri_range.x_max)) + 1);

        for (x_start..x_end) |x| {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const dist = smoothPrismDistance(&tri, vec2.xy(px, y_center), smooth_k);

            if (dist < glow_width) {
                const t = @min(@max(dist / glow_width, 0), 1);
                const alpha = falloff.apply(t) * intensity;
                const p = &ctx.buffer[local_y * ctx.width + x];
                const scale_vec: color.Color = @splat(alpha);
                p.* = p.* + glow_color * scale_vec;
            }
        }
    }
}

fn sumBuffer(buffer: []const color.Color) f32 {
    var sum: f32 = 0;
    for (buffer) |c| {
        sum += c[0] + c[1] + c[2];
    }
    return sum;
}

test "renderGlowLine produces non-zero output" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    const start = vec2.xy(5, 16);
    const end = vec2.xy(27, 16);
    const seg = segment.Segment.init(start, end);

    const config = Config{
        .color = .{ .uniform = color.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    renderLine(&ctx, seg, config, null, null);

    // Buffer should have non-zero values now
    const sum = sumBuffer(&buffer);
    try testing.expect(sum > 0);
}

test "renderGlowLine respects clipping" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    // Line across entire width
    const start = vec2.xy(0, 16);
    const end = vec2.xy(32, 16);
    const seg = segment.Segment.init(start, end);

    const config = Config{
        .color = .{ .uniform = color.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    // Clip to small triangle on left side
    const tri = prism.Prism.init(vec2.xy(5, 16), 10);

    renderLine(&ctx, seg, config, .{ .prism = &tri }, null);

    // Check that right side is still black
    const right_idx = 16 * 32 + 28;
    try testing.expectApproxEqAbs(buffer[right_idx][0], 0, 1e-6);

    // Left side should have some glow
    const left_idx = 16 * 32 + 4;
    try testing.expect(buffer[left_idx][0] > 0);
}

test "renderGlowLine with gradient color" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    const start = vec2.xy(4, 16);
    const end = vec2.xy(28, 16);
    const seg = segment.Segment.init(start, end);

    const config = Config{
        .color = .{
            .gradient = .{
                .start = color.rgb(1, 0, 0), // red
                .end = color.rgb(0, 0, 1), // blue
            },
        },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    renderLine(&ctx, seg, config, null, null);

    // Left side should be more red
    const left_idx = 16 * 32 + 6;
    try testing.expect(buffer[left_idx][0] > buffer[left_idx][2]); // r > b

    // Right side should be more blue
    const right_idx = 16 * 32 + 26;
    try testing.expect(buffer[right_idx][2] > buffer[right_idx][0]); // b > r
}

test "renderPrismGlow produces glow inside triangle" {
    var buffer: [64 * 64]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 64,
        .height = 64,
        .y_offset = 0,
        .total_height = 64,
    };

    ctx.clear();

    const tri = prism.Prism.init(vec2.xy(32, 36), 44);

    const glow_color = color.white;
    const glow_width: f32 = 8;
    const intensity: f32 = 1;

    renderPrismEdges(&ctx, tri, glow_color, glow_width, intensity, .linear);

    // Check that some glow was rendered (glow appears along edges)
    var found_glow = false;
    for (buffer) |c| {
        if (c[0] > 0) {
            found_glow = true;
            break;
        }
    }
    try testing.expect(found_glow);
}

test "renderGlowLine excludes triangle" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    ctx.clear();

    // Line across middle
    const start = vec2.xy(0, 16);
    const end = vec2.xy(32, 16);
    const seg = segment.Segment.init(start, end);

    const config = Config{
        .color = .{ .uniform = color.white },
        .width = 4,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    // Exclude triangle in center
    const exclude = prism.Prism.init(vec2.xy(16, 18), 12);

    renderLine(&ctx, seg, config, null, &exclude);

    // Center (inside exclude triangle) should be black
    const center_idx = 16 * 32 + 16;
    try testing.expectApproxEqAbs(buffer[center_idx][0], 0, 1e-6);

    // Left side (outside exclude) should have glow
    const left_idx = 16 * 32 + 4;
    try testing.expect(buffer[left_idx][0] > 0);
}

test "context with y_offset renders correct region" {
    var buffer: [16 * 8]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 16,
        .height = 8,
        .y_offset = 8, // rendering rows 8-15
        .total_height = 16,
    };

    ctx.clear();

    // Line at y=12 (within our band)
    const start = vec2.xy(0, 12);
    const end = vec2.xy(16, 12);
    const seg = segment.Segment.init(start, end);

    const config = Config{
        .color = .{ .uniform = color.white },
        .width = 2,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    renderLine(&ctx, seg, config, null, null);

    // Should have non-zero output
    const sum = sumBuffer(&buffer);
    try testing.expect(sum > 0);
}

test "context with y_offset ignores lines outside region" {
    var buffer: [16 * 8]color.Color = undefined;
    var ctx = band.Context{
        .buffer = &buffer,
        .width = 16,
        .height = 8,
        .y_offset = 8, // rendering rows 8-15
        .total_height = 16,
    };

    ctx.clear();

    // Line at y=20 (below our band which covers y=8-15)
    const start = vec2.xy(0, 20);
    const end = vec2.xy(16, 20);
    const seg = segment.Segment.init(start, end);

    const config = Config{
        .color = .{ .uniform = color.white },
        .width = 2,
        .intensity = .{ .uniform = 1 },
        .falloff = .linear,
    };

    renderLine(&ctx, seg, config, null, null);

    // Should be all black (line outside our y range)
    const sum = sumBuffer(&buffer);
    try testing.expectApproxEqAbs(sum, 0, 1e-6);
}
