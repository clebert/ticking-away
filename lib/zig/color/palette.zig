const std = @import("std");

const color_space = @import("color_space.zig");

pub const band_count: usize = 7;

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

pub const Type = Palette;

pub const Cache = struct {
    linear: [band_count]color_space.Linear,
    lab: [band_count]color_space.Oklab,

    pub fn init(pal: Type) Cache {
        const colors = palette_colors[@intFromEnum(pal)];

        var linear: [band_count]color_space.Linear = undefined;
        var lab: [band_count]color_space.Oklab = undefined;

        for (0..band_count) |i| {
            linear[i] = colors[i].toLinear();
            lab[i] = colors[i].toOklab();
        }

        return .{ .linear = linear, .lab = lab };
    }

    pub fn getColor(self: *const Cache, index: usize) color_space.Linear {
        return self.linear[index];
    }

    pub fn interpolate(self: *const Cache, t: f32) color_space.Linear {
        if (t < 0.0) {
            const oklab_infrared = (color_space.Srgb{ .r = 140, .g = 0, .b = 0 }).toOklab();
            const oklab_red = self.lab[0];
            const frac = @min(-t, 1.0);
            return color_space.Oklab.lerp(oklab_red, oklab_infrared, frac).toLinear();
        }

        if (t > 1.0) {
            const oklab_ultraviolet = (color_space.Srgb{ .r = 80, .g = 0, .b = 120 }).toOklab();
            const oklab_violet = self.lab[band_count - 1];
            const frac = @min(t - 1.0, 1.0);
            return color_space.Oklab.lerp(oklab_violet, oklab_ultraviolet, frac).toLinear();
        }

        const scaled = t * @as(f32, @floatFromInt(band_count - 1));
        const band_lo: usize = @intFromFloat(scaled);
        const band_hi: usize = @min(band_lo + 1, band_count - 1);
        const frac = scaled - @as(f32, @floatFromInt(band_lo));

        return color_space.Oklab.lerp(self.lab[band_lo], self.lab[band_hi], frac).toLinear();
    }
};

const palette_colors = [std.meta.fields(Palette).len][band_count]color_space.Srgb{
    // oklch_balanced
    .{
        .{ .r = 255, .g = 64, .b = 64 },
        .{ .r = 255, .g = 160, .b = 0 },
        .{ .r = 220, .g = 220, .b = 0 },
        .{ .r = 0, .g = 200, .b = 80 },
        .{ .r = 0, .g = 180, .b = 220 },
        .{ .r = 80, .g = 100, .b = 255 },
        .{ .r = 180, .g = 80, .b = 255 },
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
