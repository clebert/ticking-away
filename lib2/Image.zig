const std = @import("std");

const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

width: usize,
height: usize,

pub fn init(width: usize, height: usize) Self {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);

    return .{ .width = width, .height = height };
}

pub fn Band(comptime Color: type) type {
    return struct {
        buffer: []Color,
        width: usize,
        y_offset: usize,

        pub fn bandHeight(self: Band(Color)) usize {
            return self.buffer.len / self.width;
        }

        pub fn imageY(self: Band(Color), y: usize) usize {
            return self.y_offset + y;
        }

        pub fn colorAt(self: Band(Color), x: usize, y: usize) *Color {
            return &self.buffer[y * self.width + x];
        }

        pub fn toSrgb(self: Band(Linear), srgb_buffer: []Srgb) !Band(Srgb) {
            if (self.buffer.len != srgb_buffer.len) {
                return error.BufferSizeMismatch;
            }

            for (self.buffer, srgb_buffer) |linear, *srgb| {
                srgb.* = linear.toSrgb();
            }

            return .{ .buffer = srgb_buffer, .width = self.width, .y_offset = self.y_offset };
        }
    };
}

pub fn initBand(
    self: Self,
    comptime Color: type,
    buffer: []Color,
    band_height: usize,
    band_index: usize,
) !Band(Color) {
    if (self.height % band_height != 0) {
        return error.InvalidBandHeight;
    }

    if (buffer.len != self.width * band_height) {
        return error.BufferSizeMismatch;
    }

    return .{ .buffer = buffer, .width = self.width, .y_offset = band_index * band_height };
}
