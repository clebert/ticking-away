const std = @import("std");

const color = @import("../color/color.zig");
const prism = @import("../geometry/prism.zig");

/// Grain effect configuration.
pub const Config = struct {
    intensity: f32 = 0.5,
    scale: f32 = 1.0,
    threshold: f32 = 0.1,
    prism_only: bool = false,
};

/// Geometry context for grain region masking.
pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    prism: ?prism.Prism = null,
};

/// Apply film grain effect to buffer (expects sRGB space).
/// Grain is brightness-scaled and monochromatic for authentic film look.
pub fn apply(
    buffer: []color.Color,
    width: usize,
    height: usize,
    config: Config,
    geometry: ?Geometry,
) void {
    if (config.intensity <= 0.0) return;

    // Grain strength: ±6% at full intensity (~±15/255, classic film grain)
    const grain_strength = config.intensity * 0.06;

    // Brightness scaling factor
    const brightness_scale = 1.0 / @max(config.threshold, 0.01);

    // Pre-compute inverse scale for coordinate scaling
    const inv_scale = 1.0 / config.scale;

    // Pre-compute geometry radius squared if available
    const r2 = if (geometry) |geo| geo.radius * geo.radius else 0.0;

    for (0..height) |y| {
        const y_f: f32 = @floatFromInt(y);
        const py = y_f + 0.5;
        const gy: i32 = @intFromFloat(y_f * inv_scale);

        for (0..width) |x| {
            const x_f: f32 = @floatFromInt(x);
            const px = x_f + 0.5;
            const idx = y * width + x;

            // Geometry masking (circle and optional prism)
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

            // Get current sRGB values
            const red = buffer[idx][0];
            const green = buffer[idx][1];
            const blue = buffer[idx][2];

            // Calculate brightness (simple average in sRGB space)
            const brightness = (red + green + blue) / 3.0;

            // Scale grain intensity by brightness (fades to zero in dark areas)
            const brightness_factor = std.math.clamp(brightness * brightness_scale, 0.0, 1.0);

            // Generate deterministic noise using scaled coordinates
            const gx: i32 = @intFromFloat(x_f * inv_scale);
            const hash = hashPixel(gx, gy);

            // Convert hash to noise value: [-grain_strength, +grain_strength]
            const hash_f: f32 = @floatFromInt(hash & 0xFF);
            const noise = (hash_f / 255.0 - 0.5) * grain_strength * 2.0;

            // Apply brightness-scaled noise
            const grain_val = noise * brightness_factor;

            // Add grain to all channels (monochromatic grain)
            buffer[idx][0] = std.math.clamp(red + grain_val, 0.0, 1.0);
            buffer[idx][1] = std.math.clamp(green + grain_val, 0.0, 1.0);
            buffer[idx][2] = std.math.clamp(blue + grain_val, 0.0, 1.0);
        }
    }
}

/// Deterministic hash for pixel coordinates.
/// Returns a uniformly distributed 32-bit value.
pub fn hashPixel(x: i32, y: i32) u32 {
    const ux: u32 = @bitCast(x);
    const uy: u32 = @bitCast(y);
    var h = ux *% 374761393 +% uy *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}
