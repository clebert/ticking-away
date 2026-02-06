const std = @import("std");

const Srgb = @import("Srgb.zig");

const Self = @This();

pub const black: Self = .{ .vec = .{ 0, 0, 0, 1 } };
pub const white: Self = .{ .vec = .{ 1, 1, 1, 1 } };

vec: @Vector(4, f32),

pub fn init(r: f32, g: f32, b: f32, a: f32) Self {
    return .{ .vec = .{ r, g, b, a } };
}

/// https://en.wikipedia.org/wiki/Linear_interpolation
pub fn lerp(a: Self, b: Self, t: f32) Self {
    std.debug.assert(t >= 0.0 and t <= 1.0);

    const t_vec: @Vector(4, f32) = @splat(t);

    return .{ .vec = a.vec + (b.vec - a.vec) * t_vec };
}

pub fn toSrgb(self: Self) Srgb {
    if (@reduce(.And, self.vec == black.vec)) return .black;

    return .{
        .r = linearToSrgbByte(self.vec[0]),
        .g = linearToSrgbByte(self.vec[1]),
        .b = linearToSrgbByte(self.vec[2]),
        .a = @intFromFloat(@round(std.math.clamp(self.vec[3], 0.0, 1.0) * 255.0)),
    };
}

fn linearToSrgbByte(linear: f32) u8 {
    return @intFromFloat(@round(linearToSrgbComponent(std.math.clamp(linear, 0.0, 1.0)) * 255.0));
}

fn linearToSrgbComponent(linear: f32) f32 {
    if (linear <= 0.0031308) {
        return linear * 12.92;
    }

    return 1.055 * pow512(linear) - 0.055;
}

fn pow512(x: f32) f32 {
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;

    const cbrt_x = cbrt(x);
    const fourth_root_cbrt = @sqrt(@sqrt(cbrt_x));

    return cbrt_x * fourth_root_cbrt;
}

fn cbrt(x: f32) f32 {
    if (x == 0.0) return 0.0;

    const abs_x = @abs(x);

    // Initial approximation using IEEE 754 bit manipulation
    // https://en.wikipedia.org/wiki/Fast_inverse_square_root
    var y: f32 = @bitCast(@as(u32, @bitCast(abs_x)) / 3 + 709921077);

    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;

    return std.math.copysign(y, x);
}

test "lerp at t=0 returns first color" {
    const a = Self.init(0.2, 0.4, 0.6, 1.0);
    const b = Self.init(0.8, 0.6, 0.4, 0.5);
    const result = lerp(a, b, 0.0);

    try std.testing.expectEqual(a.vec, result.vec);
}

test "lerp at t=1 returns second color" {
    const a = Self.init(0.2, 0.4, 0.6, 1.0);
    const b = Self.init(0.8, 0.6, 0.4, 0.5);
    const result = lerp(a, b, 1.0);

    try std.testing.expectEqual(b.vec, result.vec);
}

test "lerp at t=0.5 returns midpoint" {
    const a = Self.init(0.0, 0.0, 0.0, 0.0);
    const b = Self.init(1.0, 1.0, 1.0, 1.0);
    const result = lerp(a, b, 0.5);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vec[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vec[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vec[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vec[3], 1e-6);
}

test "toSrgb converts black correctly" {
    const srgb = black.toSrgb();

    try std.testing.expectEqual(@as(u8, 0), srgb.r);
    try std.testing.expectEqual(@as(u8, 0), srgb.g);
    try std.testing.expectEqual(@as(u8, 0), srgb.b);
    try std.testing.expectEqual(@as(u8, 255), srgb.a);
}

test "toSrgb converts white correctly" {
    const srgb = white.toSrgb();

    try std.testing.expectEqual(@as(u8, 255), srgb.r);
    try std.testing.expectEqual(@as(u8, 255), srgb.g);
    try std.testing.expectEqual(@as(u8, 255), srgb.b);
    try std.testing.expectEqual(@as(u8, 255), srgb.a);
}

test "toSrgb rounds correctly near integer boundaries" {
    // Test value that would truncate incorrectly without @round
    // Linear 1.0 should produce sRGB 255, not 254
    const nearly_white = Self.init(0.9999, 0.9999, 0.9999, 0.9999);
    const srgb = nearly_white.toSrgb();

    try std.testing.expectEqual(@as(u8, 255), srgb.r);
    try std.testing.expectEqual(@as(u8, 255), srgb.g);
    try std.testing.expectEqual(@as(u8, 255), srgb.b);
    try std.testing.expectEqual(@as(u8, 255), srgb.a);
}

test "toSrgb clamps values outside 0-1 range" {
    const out_of_range = Self.init(-0.5, 1.5, 0.5, 2.0);
    const srgb = out_of_range.toSrgb();

    try std.testing.expectEqual(@as(u8, 0), srgb.r);
    try std.testing.expectEqual(@as(u8, 255), srgb.g);
    try std.testing.expectEqual(@as(u8, 188), srgb.b);
    try std.testing.expectEqual(@as(u8, 255), srgb.a);
}

test "sRGB round-trip preserves values within tolerance" {
    // Test that Linear -> Srgb -> Linear produces similar results
    const original = Self.init(0.5, 0.25, 0.75, 1.0);
    const srgb = original.toSrgb();
    const back = srgb.toLinear();

    // Allow for quantization error (1/255 ≈ 0.004 in normalized space, amplified by gamma)
    try std.testing.expectApproxEqAbs(original.vec[0], back.vec[0], 0.01);
    try std.testing.expectApproxEqAbs(original.vec[1], back.vec[1], 0.01);
    try std.testing.expectApproxEqAbs(original.vec[2], back.vec[2], 0.01);
    try std.testing.expectApproxEqAbs(original.vec[3], back.vec[3], 0.01);
}

test "linearToSrgbComponent applies correct gamma curve" {
    // Below threshold (0.0031308): linear * 12.92
    const low_value = linearToSrgbComponent(0.001);

    try std.testing.expectApproxEqAbs(@as(f32, 0.001 * 12.92), low_value, 1e-6);

    // At threshold
    const at_threshold = linearToSrgbComponent(0.0031308);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0031308 * 12.92), at_threshold, 1e-5);
}

test "pow512 computes x^(5/12) correctly" {
    // x^(5/12) for known values
    // 0.5^(5/12) ≈ 0.749
    const result = pow512(0.5);
    const expected = std.math.pow(f32, 0.5, 5.0 / 12.0);

    try std.testing.expectApproxEqAbs(expected, result, 1e-5);
}

test "cbrt computes cube root correctly" {
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), cbrt(8.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cbrt(0.125), 1e-5);
    try std.testing.expectEqual(@as(f32, 0.0), cbrt(0.0));
}
