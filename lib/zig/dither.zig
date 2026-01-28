const std = @import("std");

const color = @import("color.zig");
const gamma = @import("gamma.zig");
const oklab = @import("oklab.zig");

pub const ordered = @import("dither/ordered.zig");
pub const error_diffusion = @import("dither/error.zig");

/// RGB color for palette entries (sRGB, 0-255).
pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toLinear(self: Rgb) color.Color {
        return color.rgb(
            gamma.srgbToLinear(self.r),
            gamma.srgbToLinear(self.g),
            gamma.srgbToLinear(self.b),
        );
    }

    pub fn toOklab(self: Rgb) oklab.OkLab {
        return oklab.srgbToOklab(self.r, self.g, self.b);
    }
};

/// Palette type for quantization.
pub const PaletteType = enum {
    ideal,
    spectra6_inky,
    spectra6_epdopt,
};

/// Pure RGB palette for dithering (ideal target colors).
pub const palette_ideal = [_]Rgb{
    .{ .r = 0, .g = 0, .b = 0 }, // Black
    .{ .r = 255, .g = 255, .b = 255 }, // White
    .{ .r = 255, .g = 255, .b = 0 }, // Yellow
    .{ .r = 255, .g = 0, .b = 0 }, // Red
    .{ .r = 0, .g = 0, .b = 255 }, // Blue
    .{ .r = 0, .g = 255, .b = 0 }, // Green
};

/// Spectra 6 palette from Pimoroni Inky library.
pub const palette_spectra6_inky = [_]Rgb{
    .{ .r = 0, .g = 0, .b = 0 }, // Black
    .{ .r = 161, .g = 164, .b = 165 }, // Gray (device white appears grayish)
    .{ .r = 208, .g = 190, .b = 71 }, // Gold/Yellow
    .{ .r = 156, .g = 72, .b = 75 }, // Burgundy/Red
    .{ .r = 61, .g = 59, .b = 94 }, // Dark Blue
    .{ .r = 58, .g = 91, .b = 70 }, // Forest Green
};

/// Spectra 6 palette from EDP Optimize (measured values).
pub const palette_spectra6_epdopt = [_]Rgb{
    .{ .r = 25, .g = 30, .b = 33 }, // Black
    .{ .r = 232, .g = 232, .b = 232 }, // White
    .{ .r = 239, .g = 222, .b = 68 }, // Yellow
    .{ .r = 178, .g = 19, .b = 24 }, // Red
    .{ .r = 33, .g = 87, .b = 186 }, // Blue
    .{ .r = 18, .g = 95, .b = 32 }, // Green
};

/// Get palette by type.
pub fn getPalette(palette_type: PaletteType) []const Rgb {
    return switch (palette_type) {
        .ideal => &palette_ideal,
        .spectra6_inky => &palette_spectra6_inky,
        .spectra6_epdopt => &palette_spectra6_epdopt,
    };
}

/// Find closest palette color index using OkLab distance.
pub fn findClosestColor(
    col: oklab.OkLab,
    palette_oklab: []const oklab.OkLab,
    chroma_weight: f32,
) usize {
    @setFloatMode(.optimized);
    var best_idx: usize = 0;
    var best_dist: f32 = std.math.floatMax(f32);

    for (palette_oklab, 0..) |pal_col, i| {
        const dist = col.distanceSq(pal_col, chroma_weight);
        if (dist < best_dist) {
            best_dist = dist;
            best_idx = i;
        }
    }

    return best_idx;
}

/// Precomputed palette cache for efficient dithering.
pub const PaletteCache = struct {
    rgb: []const Rgb,
    linear: [max_palette_size]color.Color,
    lab: [max_palette_size]oklab.OkLab,
    count: usize,

    pub const max_palette_size: usize = 16;

    pub fn init(palette: []const Rgb) PaletteCache {
        var cache: PaletteCache = undefined;
        cache.rgb = palette;
        cache.count = @min(palette.len, max_palette_size);

        for (0..cache.count) |i| {
            cache.linear[i] = palette[i].toLinear();
            cache.lab[i] = palette[i].toOklab();
        }

        return cache;
    }

    pub fn findClosest(self: *const PaletteCache, col: oklab.OkLab, chroma_weight: f32) usize {
        return findClosestColor(col, self.lab[0..self.count], chroma_weight);
    }
};

test "palette count" {
    try std.testing.expectEqual(@as(usize, 6), palette_ideal.len);
    try std.testing.expectEqual(@as(usize, 6), palette_spectra6_inky.len);
    try std.testing.expectEqual(@as(usize, 6), palette_spectra6_epdopt.len);
}

test "find closest color" {
    const cache = PaletteCache.init(&palette_ideal);

    // Pure red should match red
    const red = oklab.srgbToOklab(255, 0, 0);
    const red_idx = cache.findClosest(red, 2.0);
    try std.testing.expectEqual(@as(usize, 3), red_idx); // Red is at index 3

    // Pure black should match black
    const black = oklab.srgbToOklab(0, 0, 0);
    const black_idx = cache.findClosest(black, 2.0);
    try std.testing.expectEqual(@as(usize, 0), black_idx); // Black is at index 0
}
