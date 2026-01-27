const std = @import("std");

const color = @import("color.zig");

pub const Falloff = enum {
    linear,
    quadratic,
    cubic,
    exponential,

    pub fn apply(self: Falloff, t: f32) f32 {
        std.debug.assert(t >= 0);
        std.debug.assert(t <= 1);

        const one_minus_t = 1 - t;

        return switch (self) {
            .linear => one_minus_t,
            .quadratic => one_minus_t * one_minus_t,
            .cubic => one_minus_t * one_minus_t * one_minus_t,
            .exponential => @exp(-3 * t) * one_minus_t,
        };
    }
};

pub const Config = struct {
    width: f32,
    falloff: Falloff = .quadratic,
    color: color.Color = color.white,
};
