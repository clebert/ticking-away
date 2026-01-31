const std = @import("std");

const color = @import("../color/color.zig");
const grain = @import("grain.zig");

const default_background: f32 = 0.1372549; // 35/255 in sRGB
const default_strength: f32 = 0.4; // 40% max darkening at corners

/// Vignette effect configuration.
pub const Config = struct {
    enabled: bool = true,
    strength: f32 = default_strength,
    background: f32 = default_background,
};

/// Geometry context for vignette (watch circle bounds).
pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
};

/// Apply vignette effect to buffer background (outside watch circle).
/// Expects buffer to be in sRGB space.
pub fn apply(
    buffer: []color.Color,
    width: usize,
    height: usize,
    config: Config,
    geometry: Geometry,
) void {
    if (!config.enabled) return;

    const strength = if (config.strength >= 0.0) config.strength else default_strength;
    const bg_base = if (config.background > 0.0) config.background else default_background;

    const cx = geometry.center_x;
    const cy = geometry.center_y;
    const radius = geometry.radius;
    const r2 = radius * radius;

    // Maximum distance from center (diagonal to corner)
    const width_f: f32 = @floatFromInt(width);
    const height_f: f32 = @floatFromInt(height);
    const max_dist = @sqrt(width_f * width_f + height_f * height_f) * 0.5;
    const inv_dist_range = 1.0 / (max_dist - radius);

    for (0..height) |y| {
        const dy = @as(f32, @floatFromInt(y)) - cy;
        const dy2 = dy * dy;

        for (0..width) |x| {
            const dx = @as(f32, @floatFromInt(x)) - cx;
            const dist2 = dx * dx + dy2;

            // Only process pixels OUTSIDE the watch circle
            if (dist2 > r2) {
                const idx = y * width + x;

                // Calculate vignette factor based on distance from center
                const dist_from_center = @sqrt(dist2);

                // Normalized distance: 0.0 at circle edge, 1.0 at max distance
                const vignette_t = std.math.clamp((dist_from_center - radius) * inv_dist_range, 0.0, 1.0);

                // Smoothstep for perceptually smoother gradient
                const smooth_t = vignette_t * vignette_t * (3.0 - 2.0 * vignette_t);

                // Vignette darkening factor: 1.0 at edge, (1.0 - strength) at max distance
                const vignette_factor = 1.0 - smooth_t * strength;

                // Apply dithering noise to break up banding in dark gradients
                const xi: i32 = @intCast(x);
                const yi: i32 = @intCast(y);
                const hash = grain.hashPixel(xi, yi);
                // Noise in range [-1, +1], scaled to ~1 unit in 0-255 space (±0.5/255)
                const dither = (@as(f32, @floatFromInt(hash & 0xFF)) / 255.0 - 0.5) * (2.0 / 255.0);

                // Final grey value with vignette and dither
                const grey = std.math.clamp(bg_base * vignette_factor + dither, 0.0, 1.0);

                // Set pixel to grey background with full opacity
                buffer[idx] = color.rgba(grey, grey, grey, 1.0);
            }
        }
    }
}
