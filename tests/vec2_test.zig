const std = @import("std");
const testing = std.testing;

const lib = @import("lib");
const vec2 = lib.vec2;

test "dot product" {
    // Orthogonal vectors have dot product 0
    const a = vec2.xy(1, 0);
    const b = vec2.xy(0, 1);
    try testing.expectApproxEqAbs(vec2.dot(a, b), 0, 1e-6);

    // Parallel vectors
    const c = vec2.xy(2, 0);
    try testing.expectApproxEqAbs(vec2.dot(a, c), 2, 1e-6);

    // General case
    const d = vec2.xy(3, 4);
    const e = vec2.xy(1, 2);
    try testing.expectApproxEqAbs(vec2.dot(d, e), 11, 1e-6); // 3*1 + 4*2 = 11
}

test "length" {
    // Zero vector
    const zero = vec2.xy(0, 0);
    try testing.expectApproxEqAbs(vec2.length(zero), 0, 1e-6);

    // Unit vector
    const unit = vec2.xy(1, 0);
    try testing.expectApproxEqAbs(vec2.length(unit), 1, 1e-6);

    // 3-4-5 triangle
    const v345 = vec2.xy(3, 4);
    try testing.expectApproxEqAbs(vec2.length(v345), 5, 1e-6);
}

test "normalize" {
    // Normal vector
    const v = vec2.xy(3, 4);
    const n = vec2.normalize(v);
    try testing.expectApproxEqAbs(vec2.length(n), 1, 1e-6);
    try testing.expectApproxEqAbs(n[0], 0.6, 1e-6);
    try testing.expectApproxEqAbs(n[1], 0.8, 1e-6);

    // Near-zero vector returns zero
    const tiny = vec2.xy(1e-10, 1e-10);
    const n_tiny = vec2.normalize(tiny);
    try testing.expectApproxEqAbs(n_tiny[0], 0, 1e-6);
    try testing.expectApproxEqAbs(n_tiny[1], 0, 1e-6);
}
