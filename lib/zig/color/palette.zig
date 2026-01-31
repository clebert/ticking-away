const std = @import("std");

const color = @import("color.zig");
const gamma = @import("gamma.zig");
const oklab = @import("oklab.zig");

pub const band_count: usize = 7;

/// Color palette identifiers for ray and gradient rendering.
pub const Palette = enum(u4) {
    oklch_balanced = 0,
    saturated = 1,
    spectral = 2,
    neon = 3,
    muted = 4,
    eink_pure = 5,
    eink_dither = 6,
    eink_full = 7,
    album_cover = 8,
    spectra6 = 9,
};

/// sRGB color triplet (0-255).
pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Type = Palette;

/// Precomputed palette values for efficient interpolation.
pub const Cache = struct {
    linear: [band_count]color.Color,
    lab: [band_count]oklab.OkLab,

    pub fn init(pal: Type) Cache {
        const colors = palette_colors[@intFromEnum(pal)];

        var linear: [band_count]color.Color = undefined;
        var lab: [band_count]oklab.OkLab = undefined;

        for (0..band_count) |i| {
            // Convert sRGB to linear RGB
            const r = gamma.srgbToLinear(colors[i].r);
            const g = gamma.srgbToLinear(colors[i].g);
            const b = gamma.srgbToLinear(colors[i].b);
            linear[i] = color.rgb(r, g, b);

            // Compute OkLab for gradient interpolation
            lab[i] = oklab.OkLab.fromLinearRgb(linear[i]);
        }

        return .{ .linear = linear, .lab = lab };
    }

    /// Get the linear color for a specific band index.
    pub fn getColor(self: *const Cache, index: usize) color.Color {
        return self.linear[index];
    }

    /// Interpolate color at position t (0.0 = red, 1.0 = violet).
    /// Handles extrapolation beyond visible spectrum (IR/UV edges).
    pub fn interpolate(self: *const Cache, t: f32) color.Color {

        // Handle extrapolation toward infrared (t < 0)
        if (t < 0.0) {
            const lab_infrared = oklab.srgbToOklab(140, 0, 0);
            const lab_red = self.lab[0];
            const frac = @min(-t, 1.0);
            const lab_interp = oklab.OkLab.lerp(lab_red, lab_infrared, frac);
            return lab_interp.toLinearRgb();
        }

        // Handle extrapolation toward ultraviolet (t > 1)
        if (t > 1.0) {
            const lab_ultraviolet = oklab.srgbToOklab(80, 0, 120);
            const lab_violet = self.lab[band_count - 1];
            const frac = @min(t - 1.0, 1.0);
            const lab_interp = oklab.OkLab.lerp(lab_violet, lab_ultraviolet, frac);
            return lab_interp.toLinearRgb();
        }

        // Map t to band index: t=0 -> band 0 (red), t=1 -> band 6 (violet)
        const scaled = t * @as(f32, @floatFromInt(band_count - 1));
        const band_lo: usize = @intFromFloat(scaled);
        const band_hi: usize = @min(band_lo + 1, band_count - 1);

        // Interpolation factor within the band
        const frac = scaled - @as(f32, @floatFromInt(band_lo));

        // Interpolate in OkLab space
        const lab_interp = oklab.OkLab.lerp(self.lab[band_lo], self.lab[band_hi], frac);
        return lab_interp.toLinearRgb();
    }
};

/// Palette colors in sRGB (0-255). Indexed by Palette enum.
const palette_colors = [std.meta.fields(Palette).len][band_count]Rgb{
    // oklch_balanced (friendly, even OkLCH hue spacing)
    .{
        .{ .r = 255, .g = 64, .b = 64 }, // Red
        .{ .r = 255, .g = 160, .b = 0 }, // Orange
        .{ .r = 220, .g = 220, .b = 0 }, // Yellow
        .{ .r = 0, .g = 200, .b = 80 }, // Green
        .{ .r = 0, .g = 180, .b = 220 }, // Cyan
        .{ .r = 80, .g = 100, .b = 255 }, // Blue
        .{ .r = 180, .g = 80, .b = 255 }, // Violet
    },
    // saturated
    .{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 128, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 128, .g = 0, .b = 255 },
    },
    // spectral
    .{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 127, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 127, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 139, .g = 0, .b = 255 },
    },
    // neon
    .{
        .{ .r = 255, .g = 20, .b = 80 },
        .{ .r = 255, .g = 100, .b = 0 },
        .{ .r = 200, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 100 },
        .{ .r = 0, .g = 200, .b = 255 },
        .{ .r = 50, .g = 50, .b = 255 },
        .{ .r = 200, .g = 0, .b = 255 },
    },
    // muted
    .{
        .{ .r = 200, .g = 80, .b = 80 },
        .{ .r = 200, .g = 140, .b = 70 },
        .{ .r = 180, .g = 180, .b = 80 },
        .{ .r = 70, .g = 160, .b = 100 },
        .{ .r = 80, .g = 150, .b = 180 },
        .{ .r = 100, .g = 110, .b = 200 },
        .{ .r = 150, .g = 100, .b = 200 },
    },
    // eink_pure
    .{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
    },
    // eink_dither
    .{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 176, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 160, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
    },
    // eink_full
    .{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 160, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 180, .b = 220 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 40, .g = 0, .b = 255 },
    },
    // album_cover
    .{
        .{ .r = 200, .g = 0, .b = 0 },
        .{ .r = 255, .g = 140, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 220, .b = 0 },
        .{ .r = 0, .g = 100, .b = 255 },
        .{ .r = 0, .g = 0, .b = 200 },
        .{ .r = 60, .g = 0, .b = 180 },
    },
    // spectra6
    .{
        .{ .r = 178, .g = 19, .b = 24 },
        .{ .r = 220, .g = 130, .b = 35 },
        .{ .r = 240, .g = 220, .b = 60 },
        .{ .r = 70, .g = 145, .b = 55 },
        .{ .r = 0, .g = 140, .b = 200 },
        .{ .r = 30, .g = 70, .b = 160 },
        .{ .r = 100, .g = 30, .b = 160 },
    },
};
