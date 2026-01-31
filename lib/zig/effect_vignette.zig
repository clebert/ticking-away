const std = @import("std");

const color_space = @import("color_space.zig");
const frame = @import("frame.zig");
const effect_grain = @import("effect_grain.zig");

const default_background: u8 = 35;
const default_strength: f32 = 0.4;

pub const Config = struct {
    enabled: bool = true,
    strength: f32 = default_strength,
    background: u8 = default_background,
};

pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
};

pub fn apply(
    band: *frame.Band,
    config: Config,
    geometry: Geometry,
) void {
    if (!config.enabled) return;

    const strength = if (config.strength >= 0.0) config.strength else default_strength;
    const bg_base: f32 = @floatFromInt(if (config.background > 0) config.background else default_background);

    const cx = geometry.center_x;
    const cy = geometry.center_y;
    const radius = geometry.radius;
    const r2 = radius * radius;

    const width_f: f32 = @floatFromInt(band.width);
    const total_height_f: f32 = @floatFromInt(band.total_height);
    const max_dist = @sqrt(width_f * width_f + total_height_f * total_height_f) * 0.5;
    const inv_dist_range = 1.0 / (max_dist - radius);

    for (0..band.height) |local_y| {
        const global_y = band.globalY(local_y);
        const dy = @as(f32, @floatFromInt(global_y)) - cy;
        const dy2 = dy * dy;

        for (0..band.width) |x| {
            const dx = @as(f32, @floatFromInt(x)) - cx;
            const dist2 = dx * dx + dy2;

            if (dist2 > r2) {
                const dist_from_center = @sqrt(dist2);
                const vignette_t = std.math.clamp((dist_from_center - radius) * inv_dist_range, 0.0, 1.0);
                const smooth_t = vignette_t * vignette_t * (3.0 - 2.0 * vignette_t);
                const vignette_factor = 1.0 - smooth_t * strength;

                const xi: i32 = @intCast(x);
                const yi: i32 = @intCast(global_y);
                const hash = effect_grain.hashPixel(xi, yi);
                const dither = (@as(f32, @floatFromInt(hash & 0xFF)) / 255.0 - 0.5) * 2.0;

                const grey: u8 = @intFromFloat(std.math.clamp(bg_base * vignette_factor + dither, 0.0, 255.0));
                band.srgbaColorAt(x, local_y).* = .{ .r = grey, .g = grey, .b = grey, .a = 255 };
            }
        }
    }
}
