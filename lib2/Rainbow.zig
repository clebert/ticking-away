const std = @import("std");

pub const ColorId = enum {
    red,
    orange,
    yellow,
    green,
    cyan,
    blue,
    violet,
};

const max_spread_radians: f32 = std.math.pi / 6.0;

const Self = @This();

spread: f32,

pub fn computeColorAngle(self: Self, base_angle: f32, color_id: ColorId) f32 {
    std.debug.assert(self.spread >= 0.0 and self.spread <= 1.0);

    const color_index: f32 = @floatFromInt(@intFromEnum(color_id));
    const color_count: f32 = @floatFromInt(@typeInfo(ColorId).@"enum".fields.len);

    // the color's position within the spectrum, normalized to [0, 1]
    const normalized_position = (color_index + 0.5) / color_count;

    const spread_radians = self.spread * max_spread_radians;
    const offset_radians = (0.5 - normalized_position) * spread_radians;

    return base_angle + offset_radians;
}
