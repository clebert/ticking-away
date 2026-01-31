const std = @import("std");

const color_space = @import("color_space.zig");

pub const Color = enum {
    red,
    orange,
    yellow,
    green,
    cyan,
    blue,
    violet,

    pub fn reverse(self: Color) Color {
        return @enumFromInt(color_count - 1 - @intFromEnum(self));
    }
};

pub const color_count: usize = @typeInfo(Color).@"enum".fields.len;

pub const PaletteType = enum(u4) {
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

pub const Palette = std.EnumArray(Color, color_space.Srgba);

pub const palette_oklch_balanced = Palette.init(.{
    .red = .{ .r = 255, .g = 64, .b = 64 },
    .orange = .{ .r = 255, .g = 160, .b = 0 },
    .yellow = .{ .r = 220, .g = 220, .b = 0 },
    .green = .{ .r = 0, .g = 200, .b = 80 },
    .cyan = .{ .r = 0, .g = 180, .b = 220 },
    .blue = .{ .r = 80, .g = 100, .b = 255 },
    .violet = .{ .r = 180, .g = 80, .b = 255 },
});

pub const palette_saturated = Palette.init(.{
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .orange = .{ .r = 255, .g = 128, .b = 0 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
    .cyan = .{ .r = 0, .g = 255, .b = 255 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .violet = .{ .r = 128, .g = 0, .b = 255 },
});

pub const palette_spectral = Palette.init(.{
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .orange = .{ .r = 255, .g = 127, .b = 0 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
    .cyan = .{ .r = 0, .g = 127, .b = 255 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .violet = .{ .r = 139, .g = 0, .b = 255 },
});

pub const palette_neon = Palette.init(.{
    .red = .{ .r = 255, .g = 20, .b = 80 },
    .orange = .{ .r = 255, .g = 100, .b = 0 },
    .yellow = .{ .r = 200, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 255, .b = 100 },
    .cyan = .{ .r = 0, .g = 200, .b = 255 },
    .blue = .{ .r = 50, .g = 50, .b = 255 },
    .violet = .{ .r = 200, .g = 0, .b = 255 },
});

pub const palette_muted = Palette.init(.{
    .red = .{ .r = 200, .g = 80, .b = 80 },
    .orange = .{ .r = 200, .g = 140, .b = 70 },
    .yellow = .{ .r = 180, .g = 180, .b = 80 },
    .green = .{ .r = 70, .g = 160, .b = 100 },
    .cyan = .{ .r = 80, .g = 150, .b = 180 },
    .blue = .{ .r = 100, .g = 110, .b = 200 },
    .violet = .{ .r = 150, .g = 100, .b = 200 },
});

pub const palette_eink_pure = Palette.init(.{
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .orange = .{ .r = 255, .g = 255, .b = 0 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
    .cyan = .{ .r = 0, .g = 255, .b = 0 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .violet = .{ .r = 0, .g = 0, .b = 255 },
});

pub const palette_eink_dither = Palette.init(.{
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .orange = .{ .r = 255, .g = 176, .b = 0 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
    .cyan = .{ .r = 0, .g = 160, .b = 255 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .violet = .{ .r = 0, .g = 0, .b = 255 },
});

pub const palette_eink_full = Palette.init(.{
    .red = .{ .r = 255, .g = 0, .b = 0 },
    .orange = .{ .r = 255, .g = 160, .b = 0 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 255, .b = 0 },
    .cyan = .{ .r = 0, .g = 180, .b = 220 },
    .blue = .{ .r = 0, .g = 0, .b = 255 },
    .violet = .{ .r = 40, .g = 0, .b = 255 },
});

pub const palette_album_cover = Palette.init(.{
    .red = .{ .r = 200, .g = 0, .b = 0 },
    .orange = .{ .r = 255, .g = 140, .b = 0 },
    .yellow = .{ .r = 255, .g = 255, .b = 0 },
    .green = .{ .r = 0, .g = 220, .b = 0 },
    .cyan = .{ .r = 0, .g = 100, .b = 255 },
    .blue = .{ .r = 0, .g = 0, .b = 200 },
    .violet = .{ .r = 60, .g = 0, .b = 180 },
});

pub const palette_spectra6 = Palette.init(.{
    .red = .{ .r = 178, .g = 19, .b = 24 },
    .orange = .{ .r = 220, .g = 130, .b = 35 },
    .yellow = .{ .r = 240, .g = 220, .b = 60 },
    .green = .{ .r = 70, .g = 145, .b = 55 },
    .cyan = .{ .r = 0, .g = 140, .b = 200 },
    .blue = .{ .r = 30, .g = 70, .b = 160 },
    .violet = .{ .r = 100, .g = 30, .b = 160 },
});

pub fn getPalette(palette_type: PaletteType) *const Palette {
    return switch (palette_type) {
        .oklch_balanced => &palette_oklch_balanced,
        .saturated => &palette_saturated,
        .spectral => &palette_spectral,
        .neon => &palette_neon,
        .muted => &palette_muted,
        .eink_pure => &palette_eink_pure,
        .eink_dither => &palette_eink_dither,
        .eink_full => &palette_eink_full,
        .album_cover => &palette_album_cover,
        .spectra6 => &palette_spectra6,
    };
}

pub const PaletteCache = struct {
    linear_colors: [color_count]color_space.Linear,
    oklab_colors: [color_count]color_space.Oklab,

    pub fn init(palette_type: PaletteType) PaletteCache {
        const palette = getPalette(palette_type);

        var linear_colors: [color_count]color_space.Linear = undefined;
        var oklab_colors: [color_count]color_space.Oklab = undefined;

        for (0..color_count) |i| {
            const color: Color = @enumFromInt(i);
            const srgb_color = palette.get(color);
            linear_colors[i] = srgb_color.toLinear();
            oklab_colors[i] = srgb_color.toOklab();
        }

        return .{ .linear_colors = linear_colors, .oklab_colors = oklab_colors };
    }

    pub fn getLinearColor(self: *const PaletteCache, color: Color) color_space.Linear {
        return self.linear_colors[@intFromEnum(color)];
    }

    pub fn interpolate(self: *const PaletteCache, t: f32) color_space.Linear {
        if (t < 0.0) {
            const oklab_infrared = (color_space.Srgba{ .r = 140, .g = 0, .b = 0 }).toOklab();
            const oklab_red = self.oklab_colors[0];
            const frac = @min(-t, 1.0);
            return color_space.Oklab.lerp(oklab_red, oklab_infrared, frac).toLinear();
        }

        if (t > 1.0) {
            const oklab_ultraviolet = (color_space.Srgba{ .r = 80, .g = 0, .b = 120 }).toOklab();
            const oklab_violet = self.oklab_colors[color_count - 1];
            const frac = @min(t - 1.0, 1.0);
            return color_space.Oklab.lerp(oklab_violet, oklab_ultraviolet, frac).toLinear();
        }

        const scaled = t * @as(f32, @floatFromInt(color_count - 1));
        const index_lo: usize = @intFromFloat(scaled);
        const index_hi: usize = @min(index_lo + 1, color_count - 1);
        const frac = scaled - @as(f32, @floatFromInt(index_lo));

        return color_space.Oklab.lerp(self.oklab_colors[index_lo], self.oklab_colors[index_hi], frac).toLinear();
    }
};

const all_palette_caches = blk: {
    @setEvalBranchQuota(100000);
    var palette_caches: [std.meta.fields(PaletteType).len]PaletteCache = undefined;
    for (0..std.meta.fields(PaletteType).len) |i| {
        palette_caches[i] = PaletteCache.init(@enumFromInt(i));
    }
    break :blk palette_caches;
};

pub fn getPaletteCache(palette_type: PaletteType) *const PaletteCache {
    return &all_palette_caches[@intFromEnum(palette_type)];
}
