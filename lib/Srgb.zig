const std = @import("std");

const Linear = @import("Linear.zig");

const Self = @This();

pub const black: Self = .{ .r = 0, .g = 0, .b = 0 };
pub const white: Self = .{ .r = 255, .g = 255, .b = 255 };
pub const transparent: Self = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

/// Near-black background tone sampled from the original album cover.
pub const background: Self = .{ .r = 9, .g = 13, .b = 12 };

r: u8,
g: u8,
b: u8,
a: u8 = 255,

pub fn toLinear(self: Self) Linear {
    return .{
        .vec = .{
            srgbByteToLinear(self.r),
            srgbByteToLinear(self.g),
            srgbByteToLinear(self.b),
            @as(f32, @floatFromInt(self.a)) / 255.0,
        },
    };
}

fn srgbByteToLinear(byte: u8) f32 {
    return srgbToLinearComponent(@as(f32, @floatFromInt(byte)) / 255.0);
}

/// Inverse sRGB transfer function: a gamma-encoded component in 0–1 to linear light.
pub fn srgbToLinearComponent(normalized: f32) f32 {
    if (normalized <= 0.04045) {
        return normalized / 12.92;
    }

    return std.math.pow(f32, (normalized + 0.055) / 1.055, 2.4);
}

pub fn clampedByte(value: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(value, 0.0, 255.0)));
}

test "toLinear converts black correctly" {
    const linear = black.toLinear();

    try std.testing.expectEqual(@as(f32, 0.0), linear.vec[0]);
    try std.testing.expectEqual(@as(f32, 0.0), linear.vec[1]);
    try std.testing.expectEqual(@as(f32, 0.0), linear.vec[2]);
    try std.testing.expectEqual(@as(f32, 1.0), linear.vec[3]);
}

test "toLinear converts white correctly" {
    const linear = white.toLinear();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), linear.vec[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), linear.vec[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), linear.vec[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), linear.vec[3], 1e-6);
}

test "toLinear converts mid-gray correctly" {
    const gray: Self = .{ .r = 188, .g = 188, .b = 188, .a = 255 };
    const linear = gray.toLinear();

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), linear.vec[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), linear.vec[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), linear.vec[2], 0.01);
}

test "toLinear preserves alpha as normalized value" {
    const half_alpha: Self = .{ .r = 0, .g = 0, .b = 0, .a = 128 };
    const linear = half_alpha.toLinear();

    try std.testing.expectApproxEqAbs(@as(f32, 128.0 / 255.0), linear.vec[3], 1e-6);
}

test "srgbByteToLinear uses linear formula below threshold" {
    const result = srgbByteToLinear(10);
    const normalized = 10.0 / 255.0;
    const expected = normalized / 12.92;

    try std.testing.expectApproxEqAbs(expected, result, 1e-6);
}

test "srgbByteToLinear uses gamma formula above threshold" {
    const result = srgbByteToLinear(128);
    const normalized = 128.0 / 255.0;
    const expected = std.math.pow(f32, (normalized + 0.055) / 1.055, 2.4);

    try std.testing.expectApproxEqAbs(expected, result, 1e-6);
}

test "round-trip Srgb to Linear and back preserves values" {
    const original: Self = .{ .r = 100, .g = 150, .b = 200, .a = 255 };
    const linear = original.toLinear();
    const back = linear.toSrgb();

    try std.testing.expectEqual(original.r, back.r);
    try std.testing.expectEqual(original.g, back.g);
    try std.testing.expectEqual(original.b, back.b);
    try std.testing.expectEqual(original.a, back.a);
}

test "clampedByte rounds and clamps to 0-255" {
    try std.testing.expectEqual(@as(u8, 0), clampedByte(-10.0));
    try std.testing.expectEqual(@as(u8, 255), clampedByte(300.0));
    try std.testing.expectEqual(@as(u8, 128), clampedByte(127.6));
    try std.testing.expectEqual(@as(u8, 127), clampedByte(127.4));
}
