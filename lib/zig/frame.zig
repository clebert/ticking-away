const std = @import("std");
const color_space = @import("color_space.zig");

pub const Range = struct {
    x_min: f32,
    x_max: f32,
};

pub const Band = struct {
    linear_colors: []color_space.Linear,
    srgba_colors: []color_space.Srgba,
    width: usize,
    height: usize,
    y_offset: usize,
    total_height: usize,

    pub inline fn linearColorAt(self: *Band, x: usize, y: usize) *color_space.Linear {
        return &self.linear_colors[y * self.width + x];
    }

    pub inline fn srgbaColorAt(self: *Band, x: usize, y: usize) *color_space.Srgba {
        return &self.srgba_colors[y * self.width + x];
    }

    pub inline fn globalY(self: *const Band, local_y: usize) usize {
        return self.y_offset + local_y;
    }

    pub fn convertToSrgba(self: *const Band) void {
        std.debug.assert(self.linear_colors.len == self.srgba_colors.len);
        for (self.linear_colors, self.srgba_colors) |linear, *srgba| {
            srgba.* = linear.toSrgba();
        }
    }
};
