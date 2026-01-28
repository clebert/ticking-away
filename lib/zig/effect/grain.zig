const std = @import("std");

const color = @import("../color.zig");
const triangle = @import("../triangle.zig");

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
    prism: ?triangle.Triangle = null,
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

    // Circle bounds
    const use_circle = geometry != null;
    const cx = if (geometry) |g| g.center_x else 0;
    const cy = if (geometry) |g| g.center_y else 0;
    const r2 = if (geometry) |g| g.radius * g.radius else 0;

    for (0..height) |y| {
        const py = @as(f32, @floatFromInt(y)) + 0.5;

        for (0..width) |x| {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const idx = y * width + x;

            // Circle mask check
            if (use_circle) {
                const dx = px - cx;
                const dy = py - cy;
                const dist_sq = dx * dx + dy * dy;
                if (dist_sq > r2) continue;

                // Prism-only check
                if (config.prism_only) {
                    if (geometry) |g| {
                        if (g.prism) |prism| {
                            // Use SIMD containsPoint4 with single point
                            const px_vec: @Vector(4, f32) = @splat(px);
                            const py_vec: @Vector(4, f32) = @splat(py);
                            const inside = prism.containsPoint4(px_vec, py_vec);
                            if (!inside[0]) continue;
                        }
                    }
                }
            }

            // Get current sRGB values
            const r = buffer[idx][0];
            const g = buffer[idx][1];
            const b = buffer[idx][2];

            // Calculate brightness (simple average in sRGB space)
            const brightness = (r + g + b) / 3.0;

            // Scale grain intensity by brightness (fades to zero in dark areas)
            const brightness_factor = clamp01(brightness * brightness_scale);

            // Generate deterministic noise using scaled coordinates
            const gx: i32 = @intFromFloat(@as(f32, @floatFromInt(x)) / config.scale);
            const gy: i32 = @intFromFloat(@as(f32, @floatFromInt(y)) / config.scale);
            const hash = hashPixel(gx, gy);

            // Convert hash to noise value: [-grain_strength, +grain_strength]
            const noise = (@as(f32, @floatFromInt(hash & 0xFF)) / 255.0 - 0.5) * grain_strength * 2.0;

            // Apply brightness-scaled noise
            const grain_val = noise * brightness_factor;

            // Add grain to all channels (monochromatic grain)
            buffer[idx][0] = clamp01(r + grain_val);
            buffer[idx][1] = clamp01(g + grain_val);
            buffer[idx][2] = clamp01(b + grain_val);
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

inline fn clamp01(x: f32) f32 {
    return @min(@max(x, 0.0), 1.0);
}

test "grain hash deterministic" {
    // Same coordinates should produce same hash
    const h1 = hashPixel(100, 200);
    const h2 = hashPixel(100, 200);
    try std.testing.expectEqual(h1, h2);

    // Different coordinates should produce different hash
    const h3 = hashPixel(101, 200);
    try std.testing.expect(h1 != h3);
}

test "grain apply" {
    var buffer = [_]color.Color{
        color.rgb(0.5, 0.5, 0.5),
        color.rgb(0.5, 0.5, 0.5),
        color.rgb(0.5, 0.5, 0.5),
        color.rgb(0.5, 0.5, 0.5),
    };

    const config = Config{ .intensity = 1.0, .scale = 1.0, .threshold = 0.1 };
    apply(&buffer, 2, 2, config, null);

    // Values should have changed but still be valid
    for (buffer) |c| {
        try std.testing.expect(c[0] >= 0.0 and c[0] <= 1.0);
        try std.testing.expect(c[1] >= 0.0 and c[1] <= 1.0);
        try std.testing.expect(c[2] >= 0.0 and c[2] <= 1.0);
    }
}
