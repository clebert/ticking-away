const std = @import("std");

const color = @import("color.zig");
const grain = @import("grain.zig");

/// Default background grey level: 35/255 in sRGB space
pub const default_background: f32 = 0.1372549;

/// Default vignette strength: 40% max darkening at corners
pub const default_strength: f32 = 0.4;

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
    @setFloatMode(.optimized);
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
                const vignette_t = clamp01((dist_from_center - radius) / (max_dist - radius));

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
                const grey = clamp01(bg_base * vignette_factor + dither);

                // Set pixel to grey background with full opacity
                buffer[idx] = color.rgba(grey, grey, grey, 1.0);
            }
        }
    }
}

inline fn clamp01(x: f32) f32 {
    @setFloatMode(.optimized);
    return @min(@max(x, 0.0), 1.0);
}

test "vignette apply" {
    var buffer = [_]color.Color{
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
        color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0), color.rgb(1, 0, 0),
    };

    const config = Config{};
    const geometry = Geometry{ .center_x = 2, .center_y = 2, .radius = 1.0 };

    apply(&buffer, 4, 4, config, geometry);

    // Corners should be grey (outside circle)
    try std.testing.expect(buffer[0][0] < 0.3); // Grey, not red
    try std.testing.expectApproxEqAbs(buffer[0][0], buffer[0][1], 0.01); // Grey (r == g)
}

test "vignette disabled" {
    var buffer = [_]color.Color{color.rgb(1, 0, 0)};

    const config = Config{ .enabled = false };
    const geometry = Geometry{ .center_x = 0.5, .center_y = 0.5, .radius = 0.1 };

    apply(&buffer, 1, 1, config, geometry);

    // Should be unchanged when disabled
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buffer[0][0], 0.001);
}
