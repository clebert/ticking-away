const std = @import("std");

const color = @import("../color/color.zig");
const gamma = @import("../color/gamma.zig");
const oklab = @import("../color/oklab.zig");

/// RGB color for palette entries (sRGB, 0-255).
pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    fn toLinear(self: Rgb) color.Color {
        return color.rgb(
            gamma.srgbToLinear(self.r),
            gamma.srgbToLinear(self.g),
            gamma.srgbToLinear(self.b),
        );
    }

    fn toOklab(self: Rgb) oklab.OkLab {
        return oklab.srgbToOklab(self.r, self.g, self.b);
    }
};

/// Palette type for quantization.
pub const PaletteType = enum {
    ideal,
    spectra6_inky,
    spectra6_epdopt,
    spectra6_trmnl,
};

/// Standard palette color indices (consistent across all palettes).
pub const PaletteIndex = enum {
    black,
    white,
    yellow,
    red,
    blue,
    green,
};

/// Palette type indexed by PaletteIndex, ensuring compile-time correctness.
pub const Palette = std.EnumArray(PaletteIndex, Rgb);

/// Pure RGB palette for dithering (ideal target colors).
pub const palette_ideal = Palette.init(.{
    .black = .{ .r = 0, .g = 0, .b = 0 },
    .white = .{ .r = 255, .g = 255, .b = 255 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
});

/// Spectra 6 palette from Pimoroni Inky library.
/// Source: https://github.com/pimoroni/inky
pub const palette_spectra6_inky = Palette.init(.{
    .black = .{ .r = 0, .g = 0, .b = 0 },
    .white = .{ .r = 161, .g = 164, .b = 165 }, // Device white appears grayish
    .yellow = .{ .r = 208, .g = 190, .b = 71 }, // Gold
    .red = .{ .r = 156, .g = 72, .b = 75 }, // Burgundy
    .blue = .{ .r = 61, .g = 59, .b = 94 }, // Dark blue
    .green = .{ .r = 58, .g = 91, .b = 70 }, // Forest green
});

/// Spectra 6 palette from EDP Optimize (measured values).
/// Source: https://github.com/Utzel-Butzel/epdoptimize
pub const palette_spectra6_epdopt = Palette.init(.{
    .black = .{ .r = 25, .g = 30, .b = 33 },
    .white = .{ .r = 232, .g = 232, .b = 232 },
    .yellow = .{ .r = 239, .g = 222, .b = 68 },
    .red = .{ .r = 178, .g = 19, .b = 24 },
    .blue = .{ .r = 33, .g = 87, .b = 186 },
    .green = .{ .r = 18, .g = 95, .b = 32 },
});

/// Spectra 6 palette from TRMNL firmware.
/// Source: https://github.com/usetrmnl/trmnl-firmware/blob/754868a57b6f47c49479167e4047e369894d2ffc/src/display.cpp#L509
pub const palette_spectra6_trmnl = Palette.init(.{
    .black = .{ .r = 0, .g = 0, .b = 0 },
    .white = .{ .r = 192, .g = 192, .b = 192 },
    .yellow = .{ .r = 192, .g = 192, .b = 0 },
    .red = .{ .r = 192, .g = 0, .b = 0 },
    .blue = .{ .r = 0, .g = 0, .b = 192 },
    .green = .{ .r = 0, .g = 192, .b = 0 },
});

/// Get palette by type.
pub fn getPalette(palette_type: PaletteType) *const Palette {
    return switch (palette_type) {
        .ideal => &palette_ideal,
        .spectra6_inky => &palette_spectra6_inky,
        .spectra6_epdopt => &palette_spectra6_epdopt,
        .spectra6_trmnl => &palette_spectra6_trmnl,
    };
}

/// Find closest palette color index using OkLab distance.
fn findClosestColor(
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
    palette: *const Palette,
    linear: [palette_size]color.Color,
    lab: [palette_size]oklab.OkLab,

    pub const palette_size: usize = @typeInfo(PaletteIndex).@"enum".fields.len;

    pub fn init(palette: *const Palette) PaletteCache {
        var cache: PaletteCache = undefined;
        cache.palette = palette;

        for (0..palette_size) |i| {
            cache.linear[i] = palette.values[i].toLinear();
            cache.lab[i] = palette.values[i].toOklab();
        }

        return cache;
    }

    pub fn findClosest(self: *const PaletteCache, col: oklab.OkLab, chroma_weight: f32) PaletteIndex {
        const idx = findClosestColor(col, &self.lab, chroma_weight);
        return @enumFromInt(idx);
    }

    pub fn getRgb(self: *const PaletteCache, idx: PaletteIndex) Rgb {
        return self.palette.get(idx);
    }
};

test "palette count" {
    try std.testing.expectEqual(6, PaletteCache.palette_size);
    try std.testing.expectEqual(6, palette_ideal.values.len);
    try std.testing.expectEqual(6, palette_spectra6_inky.values.len);
    try std.testing.expectEqual(6, palette_spectra6_epdopt.values.len);
    try std.testing.expectEqual(6, palette_spectra6_trmnl.values.len);
}

test "find closest color" {
    const cache = PaletteCache.init(&palette_ideal);

    // Pure red should match red
    const red = oklab.srgbToOklab(255, 0, 0);
    const red_idx = cache.findClosest(red, 2.0);
    try std.testing.expectEqual(PaletteIndex.red, red_idx);

    // Pure black should match black
    const black = oklab.srgbToOklab(0, 0, 0);
    const black_idx = cache.findClosest(black, 2.0);
    try std.testing.expectEqual(PaletteIndex.black, black_idx);
}
