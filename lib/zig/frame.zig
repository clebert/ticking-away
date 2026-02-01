const std = @import("std");

const color_space = @import("color_space.zig");

pub const Range = struct {
    x_min: f32,
    x_max: f32,
};

pub const Geometry = struct {
    width: usize,
    height: usize,
    y_offset: usize,
    total_height: usize,

    pub inline fn globalY(self: Geometry, local_y: usize) usize {
        return self.y_offset + local_y;
    }
};

pub const BandLinear = struct {
    colors: []color_space.Linear,
    geometry: *const Geometry,

    pub inline fn colorAt(self: BandLinear, x: usize, y: usize) *color_space.Linear {
        return &self.colors[y * self.geometry.width + x];
    }

    pub fn toSrgba(self: BandLinear, srgba_colors: []color_space.Srgba) BandSrgba {
        std.debug.assert(self.colors.len == srgba_colors.len);
        for (self.colors, srgba_colors) |linear, *srgba| {
            srgba.* = linear.toSrgba();
        }
        return BandSrgba{
            .colors = srgba_colors,
            .geometry = self.geometry,
        };
    }
};

pub const BandSrgba = struct {
    colors: []color_space.Srgba,
    geometry: *const Geometry,

    pub inline fn colorAt(self: BandSrgba, x: usize, y: usize) *color_space.Srgba {
        return &self.colors[y * self.geometry.width + x];
    }
};
