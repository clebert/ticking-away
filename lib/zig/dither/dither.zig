const std = @import("std");

const color_space = @import("../color/color_space.zig");

pub const PaletteType = enum {
    ideal,
    spectra6_inky,
    spectra6_epdopt,
    spectra6_trmnl,
};

pub const PaletteIndex = enum {
    black,
    white,
    yellow,
    red,
    blue,
    green,
};

pub const Palette = std.EnumArray(PaletteIndex, color_space.Srgb);

pub const palette_ideal = Palette.init(.{
    .black = .{ .r = 0, .g = 0, .b = 0 },
    .white = .{ .r = 255, .g = 255, .b = 255 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
});

pub const palette_spectra6_inky = Palette.init(.{
    .black = .{ .r = 0, .g = 0, .b = 0 },
    .white = .{ .r = 161, .g = 164, .b = 165 },
    .yellow = .{ .r = 208, .g = 190, .b = 71 },
    .red = .{ .r = 156, .g = 72, .b = 75 },
    .blue = .{ .r = 61, .g = 59, .b = 94 },
    .green = .{ .r = 58, .g = 91, .b = 70 },
});

pub const palette_spectra6_epdopt = Palette.init(.{
    .black = .{ .r = 25, .g = 30, .b = 33 },
    .white = .{ .r = 232, .g = 232, .b = 232 },
    .yellow = .{ .r = 239, .g = 222, .b = 68 },
    .red = .{ .r = 178, .g = 19, .b = 24 },
    .blue = .{ .r = 33, .g = 87, .b = 186 },
    .green = .{ .r = 18, .g = 95, .b = 32 },
});

pub const palette_spectra6_trmnl = Palette.init(.{
    .black = .{ .r = 0, .g = 0, .b = 0 },
    .white = .{ .r = 192, .g = 192, .b = 192 },
    .yellow = .{ .r = 192, .g = 192, .b = 0 },
    .red = .{ .r = 192, .g = 0, .b = 0 },
    .blue = .{ .r = 0, .g = 0, .b = 192 },
    .green = .{ .r = 0, .g = 192, .b = 0 },
});

pub fn getPalette(palette_type: PaletteType) *const Palette {
    return switch (palette_type) {
        .ideal => &palette_ideal,
        .spectra6_inky => &palette_spectra6_inky,
        .spectra6_epdopt => &palette_spectra6_epdopt,
        .spectra6_trmnl => &palette_spectra6_trmnl,
    };
}

fn findClosestColor(
    col: color_space.Oklab,
    palette_oklab: []const color_space.Oklab,
    chroma_weight: f32,
) usize {
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

pub const PaletteCache = struct {
    palette: *const Palette,
    linear: [palette_size]color_space.Linear,
    lab: [palette_size]color_space.Oklab,

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

    pub fn findClosest(self: *const PaletteCache, col: color_space.Oklab, chroma_weight: f32) PaletteIndex {
        const idx = findClosestColor(col, &self.lab, chroma_weight);
        return @enumFromInt(idx);
    }

    pub fn getRgb(self: *const PaletteCache, idx: PaletteIndex) color_space.Srgb {
        return self.palette.get(idx);
    }
};
