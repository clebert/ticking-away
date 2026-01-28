const std = @import("std");

const color = @import("color.zig");

/// Convert a single float channel (0.0-1.0) to u8 (0-255).
pub inline fn floatToU8(f: f32) u8 {
    const clamped = @min(@max(f, 0.0), 1.0);
    return @intFromFloat(clamped * 255.0 + 0.5);
}

/// Convert a Color (linear RGBA float) to sRGB u8 (assumes already in sRGB).
pub inline fn colorToRgba(c: color.Color) [4]u8 {
    return .{
        floatToU8(c[0]),
        floatToU8(c[1]),
        floatToU8(c[2]),
        floatToU8(c[3]),
    };
}

/// SIMD 4-wide float to u8 conversion.
pub inline fn float4ToU8(v: @Vector(4, f32)) @Vector(4, u8) {
    const zero: @Vector(4, f32) = @splat(0.0);
    const one: @Vector(4, f32) = @splat(1.0);
    const scale: @Vector(4, f32) = @splat(255.0);
    const half: @Vector(4, f32) = @splat(0.5);

    const clamped = @min(@max(v, zero), one);
    const scaled = clamped * scale + half;

    return .{
        @intFromFloat(scaled[0]),
        @intFromFloat(scaled[1]),
        @intFromFloat(scaled[2]),
        @intFromFloat(scaled[3]),
    };
}

/// Apply direct quantization to a color buffer.
/// Converts float RGBA (0.0-1.0) to u8 RGBA (0-255).
pub fn apply(buffer: []const color.Color, out_rgba: []u8) void {
    const pixel_count = buffer.len;
    std.debug.assert(out_rgba.len >= pixel_count * 4);

    for (0..pixel_count) |i| {
        const rgba = float4ToU8(buffer[i]);
        const out_idx = i * 4;
        out_rgba[out_idx] = rgba[0];
        out_rgba[out_idx + 1] = rgba[1];
        out_rgba[out_idx + 2] = rgba[2];
        out_rgba[out_idx + 3] = rgba[3];
    }
}

/// Apply direct quantization with dimensions.
pub fn applyWithDimensions(
    buffer: []const color.Color,
    out_rgba: []u8,
    width: usize,
    height: usize,
) void {
    std.debug.assert(buffer.len == width * height);
    apply(buffer, out_rgba);
}

test "float to u8 conversion" {
    try std.testing.expectEqual(@as(u8, 0), floatToU8(0.0));
    try std.testing.expectEqual(@as(u8, 255), floatToU8(1.0));
    try std.testing.expectEqual(@as(u8, 128), floatToU8(0.5)); // 127.5 rounds to 128
    try std.testing.expectEqual(@as(u8, 0), floatToU8(-0.5)); // Clamped
    try std.testing.expectEqual(@as(u8, 255), floatToU8(1.5)); // Clamped
}

test "SIMD float4 to u8" {
    const v: @Vector(4, f32) = .{ 0.0, 0.5, 1.0, 0.25 };
    const result = float4ToU8(v);

    try std.testing.expectEqual(@as(u8, 0), result[0]);
    try std.testing.expectEqual(@as(u8, 128), result[1]);
    try std.testing.expectEqual(@as(u8, 255), result[2]);
    try std.testing.expectEqual(@as(u8, 64), result[3]); // 63.75 rounds to 64
}

test "apply quantization" {
    const buffer = [_]color.Color{
        color.rgba(0.0, 0.5, 1.0, 1.0),
        color.rgba(0.25, 0.75, 0.0, 0.5),
    };

    var out: [8]u8 = undefined;
    apply(&buffer, &out);

    // First pixel
    try std.testing.expectEqual(@as(u8, 0), out[0]); // R
    try std.testing.expectEqual(@as(u8, 128), out[1]); // G
    try std.testing.expectEqual(@as(u8, 255), out[2]); // B
    try std.testing.expectEqual(@as(u8, 255), out[3]); // A

    // Second pixel
    try std.testing.expectEqual(@as(u8, 64), out[4]); // R
    try std.testing.expectEqual(@as(u8, 191), out[5]); // G (0.75 * 255 + 0.5 = 191.75)
    try std.testing.expectEqual(@as(u8, 0), out[6]); // B
    try std.testing.expectEqual(@as(u8, 128), out[7]); // A
}
