const color = @import("../color/color.zig");

/// Convert a single float channel [0,1] to u8 [0,255].
pub inline fn floatToByte(v: f32) u8 {
    @setFloatMode(.optimized);
    const clamped = @min(@max(v, 0.0), 1.0);
    return @intFromFloat(clamped * 255.0);
}

/// Write float Color buffer to RGBA8 bytes (4 bytes per pixel).
pub fn writeRgba(buffer: []const color.Color, out: []u8) void {
    for (buffer, 0..) |c, i| {
        const idx = i * 4;
        out[idx] = floatToByte(c[0]);
        out[idx + 1] = floatToByte(c[1]);
        out[idx + 2] = floatToByte(c[2]);
        out[idx + 3] = 255;
    }
}

/// Write float Color buffer to RGB565 bytes (2 bytes per pixel, big-endian).
/// Suitable for e-ink displays and other embedded devices.
pub fn writeRgb565(buffer: []const color.Color, out: []u8) void {
    @setFloatMode(.optimized);
    for (buffer, 0..) |c, i| {
        const r5: u16 = @intFromFloat(@min(@max(c[0], 0.0), 1.0) * 31.0);
        const g6: u16 = @intFromFloat(@min(@max(c[1], 0.0), 1.0) * 63.0);
        const b5: u16 = @intFromFloat(@min(@max(c[2], 0.0), 1.0) * 31.0);
        const rgb565 = (r5 << 11) | (g6 << 5) | b5;
        const idx = i * 2;
        out[idx] = @truncate(rgb565 >> 8);
        out[idx + 1] = @truncate(rgb565);
    }
}

/// Output format specification.
pub const Format = enum {
    /// 4 bytes per pixel (R, G, B, A)
    rgba8,
    /// 2 bytes per pixel, big-endian (for e-ink displays)
    rgb565,
};

/// Write buffer to output in the specified format.
pub fn write(buffer: []const color.Color, out: []u8, format: Format) void {
    switch (format) {
        .rgba8 => writeRgba(buffer, out),
        .rgb565 => writeRgb565(buffer, out),
    }
}
