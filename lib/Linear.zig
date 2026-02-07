const std = @import("std");

const Oklab = @import("Oklab.zig");
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

/// https://bottosson.github.io/posts/oklab/
pub fn toOklab(self: Self) Oklab {
    const r = self.vec[0];
    const g = self.vec[1];
    const b = self.vec[2];

    // Linear RGB → LMS
    const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    // LMS → LMS (cube roots)
    const lp = cubeRoot(l);
    const mp = cubeRoot(m);
    const sp = cubeRoot(s);

    // LMS (cube roots) → Oklab
    return .{ .vec = .{
        0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
        1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
        0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp,
        self.vec[3],
    } };
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

const srgb_lut: [4096]u8 = blk: {
    @setEvalBranchQuota(100_000);

    var table: [4096]u8 = undefined;

    for (0..4096) |i| {
        const linear: f32 = @as(f32, @floatFromInt(i)) / 4095.0;

        table[i] = @intFromFloat(@round(linearToSrgbComponent(linear) * 255.0));
    }

    break :blk table;
};

fn linearToSrgbByte(linear: f32) u8 {
    const clamped = std.math.clamp(linear, 0.0, 1.0);
    const index: usize = @intFromFloat(@round(clamped * 4095.0));

    return srgb_lut[index];
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

    const cube_root_x = cubeRoot(x);
    const fourth_root_cube_root = @sqrt(@sqrt(cube_root_x));

    return cube_root_x * fourth_root_cube_root;
}

fn cubeRoot(x: f32) f32 {
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

test "cubeRoot computes cube root correctly" {
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), cubeRoot(8.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cubeRoot(0.125), 1e-5);
    try std.testing.expectEqual(@as(f32, 0.0), cubeRoot(0.0));
}

test "toOklab produces expected L for white" {
    const oklab = white.toOklab();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), oklab.vec[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), oklab.vec[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), oklab.vec[2], 1e-4);
}

test "round-trip Linear → Oklab → Linear preserves values" {
    const original = Self.init(0.4, 0.6, 0.2, 1.0);
    const back = original.toOklab().toLinear();

    try std.testing.expectApproxEqAbs(original.vec[0], back.vec[0], 1e-5);
    try std.testing.expectApproxEqAbs(original.vec[1], back.vec[1], 1e-5);
    try std.testing.expectApproxEqAbs(original.vec[2], back.vec[2], 1e-5);
    try std.testing.expectApproxEqAbs(original.vec[3], back.vec[3], 1e-5);
}
