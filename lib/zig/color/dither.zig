const std = @import("std");

const color_space = @import("color_space.zig");

pub const PaletteType = enum {
    ideal,
    spectra6_inky,
    spectra6_epdopt,
    spectra6_trmnl,
};

pub const Color = enum {
    black,
    white,
    yellow,
    red,
    blue,
    green,
};

pub const color_count: usize = @typeInfo(Color).@"enum".fields.len;

pub const Palette = std.EnumArray(Color, color_space.Srgb);

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
    oklab: color_space.Oklab,
    palette_oklab: []const color_space.Oklab,
    chroma_weight: f32,
) usize {
    var best_index: usize = 0;
    var best_distance: f32 = std.math.floatMax(f32);

    for (palette_oklab, 0..) |palette_color, i| {
        const distance = oklab.distanceSq(palette_color, chroma_weight);
        if (distance < best_distance) {
            best_distance = distance;
            best_index = i;
        }
    }

    return best_index;
}

pub const PaletteCache = struct {
    srgb_colors: [color_count]color_space.Srgb,
    linear_colors: [color_count]color_space.Linear,
    oklab_colors: [color_count]color_space.Oklab,

    pub fn init(palette_type: PaletteType) PaletteCache {
        const palette = getPalette(palette_type);

        var srgb_colors: [color_count]color_space.Srgb = undefined;
        var linear_colors: [color_count]color_space.Linear = undefined;
        var oklab_colors: [color_count]color_space.Oklab = undefined;

        for (0..color_count) |i| {
            const color: Color = @enumFromInt(i);
            const srgb_color = palette.get(color);
            srgb_colors[i] = srgb_color;
            linear_colors[i] = srgb_color.toLinear();
            oklab_colors[i] = srgb_color.toOklab();
        }

        return .{
            .srgb_colors = srgb_colors,
            .linear_colors = linear_colors,
            .oklab_colors = oklab_colors,
        };
    }

    pub fn findClosest(self: *const PaletteCache, oklab: color_space.Oklab, chroma_weight: f32) Color {
        const index = findClosestColor(oklab, &self.oklab_colors, chroma_weight);
        return @enumFromInt(index);
    }

    pub fn getSrgbColor(self: *const PaletteCache, color: Color) color_space.Srgb {
        return self.srgb_colors[@intFromEnum(color)];
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
