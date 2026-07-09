const std = @import("std");

const Srgb = @import("Srgb.zig");

const Self = @This();

vector: @Vector(4, f32),

pub const black: Self = .{ .vector = .{ 0, 0, 0, 1 } };
pub const white: Self = .{ .vector = .{ 1, 1, 1, 1 } };
pub const transparent: Self = .{ .vector = .{ 0, 0, 0, 0 } };

const srgb_lookup_table: [4096]u8 = blk: {
    @setEvalBranchQuota(100_000);

    var table: [4096]u8 = undefined;

    for (0..4096) |i| {
        const linear: f32 = @as(f32, @floatFromInt(i)) / 4095.0;

        table[i] = @intFromFloat(@round(toSrgbComponent(linear) * 255.0));
    }

    break :blk table;
};

pub fn init(r: f32, g: f32, b: f32, a: f32) Self {
    return .{ .vector = .{ r, g, b, a } };
}

pub fn lerp(a: Self, b: Self, t: f32) Self {
    std.debug.assert(t >= 0.0 and t <= 1.0);

    const t_vector: @Vector(4, f32) = @splat(t);

    return .{ .vector = a.vector + (b.vector - a.vector) * t_vector };
}

pub fn toSrgb(self: Self) Srgb {
    // Exact fast paths for the flat pixels that dominate the frame.
    if (@reduce(.And, self.vector == black.vector)) return .black;
    if (@reduce(.And, self.vector == transparent.vector)) return .transparent;

    return .{
        .r = toSrgbByte(self.vector[0]),
        .g = toSrgbByte(self.vector[1]),
        .b = toSrgbByte(self.vector[2]),
        .a = Srgb.clampedByte(self.vector[3] * 255.0),
    };
}

fn toSrgbByte(linear: f32) u8 {
    const clamped = std.math.clamp(linear, 0.0, 1.0);
    const index: usize = @intFromFloat(@round(clamped * 4095.0));

    return srgb_lookup_table[index];
}

pub fn toSrgbComponent(linear: f32) f32 {
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

// Only valid for non-negative inputs: all callers pass LMS or clamped linear RGB values.
fn cubeRoot(x: f32) f32 {
    std.debug.assert(x >= 0.0);

    if (x == 0.0) return 0.0;

    // Initial guess via IEEE-754 bit manipulation (cube-root nth-root trick),
    // refined by Newton iterations on f(y) = y^3 - x.
    var y: f32 = @bitCast(@divFloor(@as(u32, @bitCast(x)), 3) + 709921077);

    y = (2.0 * y + x / (y * y)) / 3.0;
    y = (2.0 * y + x / (y * y)) / 3.0;
    y = (2.0 * y + x / (y * y)) / 3.0;

    return y;
}

test "lerp at t=0 returns first color" {
    const a = Self.init(0.2, 0.4, 0.6, 1.0);
    const b = Self.init(0.8, 0.6, 0.4, 0.5);
    const result = lerp(a, b, 0.0);

    try std.testing.expectEqual(a.vector, result.vector);
}

test "lerp at t=1 returns second color" {
    const a = Self.init(0.2, 0.4, 0.6, 1.0);
    const b = Self.init(0.8, 0.6, 0.4, 0.5);
    const result = lerp(a, b, 1.0);

    try std.testing.expectEqual(b.vector, result.vector);
}

test "lerp at t=0.5 returns midpoint" {
    const a = Self.init(0.0, 0.0, 0.0, 0.0);
    const b = Self.init(1.0, 1.0, 1.0, 1.0);
    const result = lerp(a, b, 0.5);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vector[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vector[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vector[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.vector[3], 1e-6);
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
    // Guards against truncation: 0.9999 must round to 255, not 254.
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
    const original = Self.init(0.5, 0.25, 0.75, 1.0);
    const srgb = original.toSrgb();
    const back = srgb.toLinear();

    // 0.01 tolerance: 1/255 quantization amplified by gamma.
    try std.testing.expectApproxEqAbs(original.vector[0], back.vector[0], 0.01);
    try std.testing.expectApproxEqAbs(original.vector[1], back.vector[1], 0.01);
    try std.testing.expectApproxEqAbs(original.vector[2], back.vector[2], 0.01);
    try std.testing.expectApproxEqAbs(original.vector[3], back.vector[3], 0.01);
}

test "toSrgbComponent applies correct gamma curve" {
    const low_value = toSrgbComponent(0.001);

    try std.testing.expectApproxEqAbs(@as(f32, 0.001 * 12.92), low_value, 1e-6);

    const at_threshold = toSrgbComponent(0.0031308);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0031308 * 12.92), at_threshold, 1e-5);
}

test "pow512 computes x^(5/12) correctly" {
    const result = pow512(0.5);
    const expected = std.math.pow(f32, 0.5, 5.0 / 12.0);

    try std.testing.expectApproxEqAbs(expected, result, 1e-5);
}

test "cubeRoot computes cube root correctly" {
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), cubeRoot(8.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cubeRoot(0.125), 1e-5);
    try std.testing.expectEqual(@as(f32, 0.0), cubeRoot(0.0));
}
