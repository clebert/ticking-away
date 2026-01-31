const color_space = @import("../color/color_space.zig");

inline fn floatToByte(v: f32) u8 {
    const clamped = @min(@max(v, 0.0), 1.0);
    return @intFromFloat(clamped * 255.0);
}

pub fn writeRgba(linear_colors: []const color_space.Linear, srgba_colors: []u8) void {
    for (linear_colors, 0..) |c, i| {
        const idx = i * 4;
        srgba_colors[idx] = floatToByte(c.vec[0]);
        srgba_colors[idx + 1] = floatToByte(c.vec[1]);
        srgba_colors[idx + 2] = floatToByte(c.vec[2]);
        srgba_colors[idx + 3] = floatToByte(c.vec[3]);
    }
}

fn writeRgb565(linear_colors: []const color_space.Linear, rgb565_colors: []u8) void {
    for (linear_colors, 0..) |c, i| {
        const r5: u16 = @intFromFloat(@min(@max(c.vec[0], 0.0), 1.0) * 31.0);
        const g6: u16 = @intFromFloat(@min(@max(c.vec[1], 0.0), 1.0) * 63.0);
        const b5: u16 = @intFromFloat(@min(@max(c.vec[2], 0.0), 1.0) * 31.0);
        const rgb565 = (r5 << 11) | (g6 << 5) | b5;
        const idx = i * 2;
        rgb565_colors[idx] = @truncate(rgb565 >> 8);
        rgb565_colors[idx + 1] = @truncate(rgb565);
    }
}

pub const Format = enum {
    rgba8,
    rgb565,
};

pub fn write(linear_colors: []const color_space.Linear, output_colors: []u8, format: Format) void {
    switch (format) {
        .rgba8 => writeRgba(linear_colors, output_colors),
        .rgb565 => writeRgb565(linear_colors, output_colors),
    }
}
