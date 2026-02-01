const std = @import("std");

const color_space = @import("color_space.zig");
const frame = @import("frame.zig");
const Prism = @import("Prism.zig");

pub const Config = struct {
    intensity: f32 = 0.5,
    scale: f32 = 1.0,
    threshold: f32 = 0.1,
    prism_only: bool = false,
};

pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    prism: ?Prism = null,
};

pub fn apply(
    band_srgba: *frame.BandSrgba,
    config: Config,
    geometry: ?Geometry,
) void {
    if (config.intensity <= 0.0) return;

    const grain_strength = config.intensity * 0.06 * 255.0;
    const threshold_u8: f32 = config.threshold * 255.0;
    const inv_scale = 1.0 / config.scale;
    const r2 = if (geometry) |geo| geo.radius * geo.radius else 0.0;
    const band_geometry = band_srgba.geometry;

    for (0..band_geometry.height) |local_y| {
        const global_y = band_geometry.globalY(local_y);
        const y_f: f32 = @floatFromInt(global_y);
        const py = y_f + 0.5;
        const gy: i32 = @intFromFloat(y_f * inv_scale);

        for (0..band_geometry.width) |x| {
            const x_f: f32 = @floatFromInt(x);
            const px = x_f + 0.5;

            if (geometry) |geo| {
                const dx = px - geo.center_x;
                const dy = py - geo.center_y;
                if (dx * dx + dy * dy > r2) continue;

                if (config.prism_only) {
                    if (geo.prism) |p| {
                        if (!p.containsPoint(px, py)) continue;
                    }
                }
            }

            const srgba = band_srgba.colorAt(x, local_y);
            const red: f32 = @floatFromInt(srgba.r);
            const green: f32 = @floatFromInt(srgba.g);
            const blue: f32 = @floatFromInt(srgba.b);

            const brightness = (red + green + blue) / 3.0;
            const brightness_factor = std.math.clamp(brightness / @max(threshold_u8, 1.0), 0.0, 1.0);

            const gx: i32 = @intFromFloat(x_f * inv_scale);
            const hash = hashPixel(gx, gy);

            const hash_f: f32 = @floatFromInt(hash & 0xFF);
            const noise = (hash_f / 255.0 - 0.5) * grain_strength * 2.0;
            const grain_val = noise * brightness_factor;

            srgba.r = @intFromFloat(std.math.clamp(red + grain_val, 0.0, 255.0));
            srgba.g = @intFromFloat(std.math.clamp(green + grain_val, 0.0, 255.0));
            srgba.b = @intFromFloat(std.math.clamp(blue + grain_val, 0.0, 255.0));
        }
    }
}

pub fn hashPixel(x: i32, y: i32) u32 {
    const ux: u32 = @bitCast(x);
    const uy: u32 = @bitCast(y);
    var h = ux *% 374761393 +% uy *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}
