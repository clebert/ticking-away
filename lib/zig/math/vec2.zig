const std = @import("std");
const testing = std.testing;

pub const Vec2 = @Vector(2, f32);

pub inline fn xy(x: f32, y: f32) Vec2 {
    return .{ x, y };
}

pub inline fn dot(a: Vec2, b: Vec2) f32 {
    @setFloatMode(.optimized);
    return @reduce(.Add, a * b);
}

pub inline fn lengthSq(v: Vec2) f32 {
    return dot(v, v);
}

pub inline fn length(v: Vec2) f32 {
    @setFloatMode(.optimized);
    return @sqrt(lengthSq(v));
}

pub inline fn normalize(v: Vec2) Vec2 {
    @setFloatMode(.optimized);
    const len = length(v);
    if (len < 1e-9) return xy(0, 0);
    return v / @as(Vec2, @splat(len));
}

test "dot product" {
    // Orthogonal vectors have dot product 0
    const a = xy(1, 0);
    const b = xy(0, 1);
    try testing.expectApproxEqAbs(dot(a, b), 0, 1e-6);

    // Parallel vectors
    const c = xy(2, 0);
    try testing.expectApproxEqAbs(dot(a, c), 2, 1e-6);

    // General case
    const d = xy(3, 4);
    const e = xy(1, 2);
    try testing.expectApproxEqAbs(dot(d, e), 11, 1e-6); // 3*1 + 4*2 = 11
}

test "length" {
    // Zero vector
    const zero = xy(0, 0);
    try testing.expectApproxEqAbs(length(zero), 0, 1e-6);

    // Unit vector
    const unit = xy(1, 0);
    try testing.expectApproxEqAbs(length(unit), 1, 1e-6);

    // 3-4-5 triangle
    const v345 = xy(3, 4);
    try testing.expectApproxEqAbs(length(v345), 5, 1e-6);
}

test "normalize" {
    // Normal vector
    const v = xy(3, 4);
    const n = normalize(v);
    try testing.expectApproxEqAbs(length(n), 1, 1e-6);
    try testing.expectApproxEqAbs(n[0], 0.6, 1e-6);
    try testing.expectApproxEqAbs(n[1], 0.8, 1e-6);

    // Near-zero vector returns zero
    const tiny = xy(1e-10, 1e-10);
    const n_tiny = normalize(tiny);
    try testing.expectApproxEqAbs(n_tiny[0], 0, 1e-6);
    try testing.expectApproxEqAbs(n_tiny[1], 0, 1e-6);
}
