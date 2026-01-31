const color_space = @import("../color/color_space.zig");

inline fn floatToByte(v: f32) u8 {
    const clamped = @min(@max(v, 0.0), 1.0);
    return @intFromFloat(clamped * 255.0);
}

pub fn writeRgba(buffer: []const color_space.Linear, out: []u8) void {
    for (buffer, 0..) |c, i| {
        const idx = i * 4;
        out[idx] = floatToByte(c.vec[0]);
        out[idx + 1] = floatToByte(c.vec[1]);
        out[idx + 2] = floatToByte(c.vec[2]);
        out[idx + 3] = floatToByte(c.vec[3]);
    }
}

fn writeRgb565(buffer: []const color_space.Linear, out: []u8) void {
    for (buffer, 0..) |c, i| {
        const r5: u16 = @intFromFloat(@min(@max(c.vec[0], 0.0), 1.0) * 31.0);
        const g6: u16 = @intFromFloat(@min(@max(c.vec[1], 0.0), 1.0) * 63.0);
        const b5: u16 = @intFromFloat(@min(@max(c.vec[2], 0.0), 1.0) * 31.0);
        const rgb565 = (r5 << 11) | (g6 << 5) | b5;
        const idx = i * 2;
        out[idx] = @truncate(rgb565 >> 8);
        out[idx + 1] = @truncate(rgb565);
    }
}

pub const Format = enum {
    rgba8,
    rgb565,
};

pub fn write(buffer: []const color_space.Linear, out: []u8, format: Format) void {
    switch (format) {
        .rgba8 => writeRgba(buffer, out),
        .rgb565 => writeRgb565(buffer, out),
    }
}
