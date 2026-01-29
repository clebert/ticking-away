const std = @import("std");

const color = @import("../color/color.zig");

pub const Falloff = enum {
    linear,
    quadratic,
    cubic,
    exponential,

    pub fn apply(self: Falloff, t: f32) f32 {
        @setFloatMode(.optimized);
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

    color: union(enum) {
        uniform: color.Color,
        gradient: struct { start: color.Color, end: color.Color },
    } = .{ .uniform = color.white },

    /// Intensity along the line (start to end). Used for fade-out effects.
    intensity: union(enum) {
        uniform: f32,
        gradient: struct { start: f32, end: f32 },
    } = .{ .uniform = 1.0 },
};
