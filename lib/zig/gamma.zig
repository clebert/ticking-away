const std = @import("std");

const color = @import("color.zig");

/// Convert sRGB byte (0-255) to linear float (0.0-1.0).
/// Uses the standard sRGB transfer function.
pub fn srgbToLinear(srgb: u8) f32 {
    const s = @as(f32, @floatFromInt(srgb)) / 255.0;
    if (s <= 0.04045) {
        return s / 12.92;
    }
    return std.math.pow(f32, (s + 0.055) / 1.055, 2.4);
}

/// Convert linear float (0.0-1.0) to sRGB float (0.0-1.0).
/// Uses accurate x^(5/12) via cbrt * sqrt(sqrt(cbrt(x))) for dark regions.
pub fn linearToSrgb(linear: f32) f32 {
    if (linear <= 0.0031308) {
        return linear * 12.92;
    }
    return 1.055 * pow512(linear) - 0.055;
}

/// SIMD 4-wide linear to sRGB conversion.
pub fn linearToSrgb4(linear: @Vector(4, f32)) @Vector(4, f32) {
    const threshold: @Vector(4, f32) = @splat(0.0031308);
    const scale: @Vector(4, f32) = @splat(12.92);
    const low_result = linear * scale;

    const pow_result = pow512Vec4(linear);
    const a: @Vector(4, f32) = @splat(1.055);
    const b: @Vector(4, f32) = @splat(0.055);
    const high_result = a * pow_result - b;

    return @select(f32, linear <= threshold, low_result, high_result);
}

/// Apply gamma correction to an entire buffer in-place.
/// Clamps values and converts from linear to sRGB space.
pub fn applyToBuffer(buffer: []color.Color) void {
    var i: usize = 0;

    // Process 4 colors at a time using SIMD
    while (i + 4 <= buffer.len) : (i += 4) {
        // Load and clamp R values
        var r_vec: @Vector(4, f32) = .{
            clamp01(buffer[i][0]),
            clamp01(buffer[i + 1][0]),
            clamp01(buffer[i + 2][0]),
            clamp01(buffer[i + 3][0]),
        };
        r_vec = linearToSrgb4(r_vec);

        // Load and clamp G values
        var g_vec: @Vector(4, f32) = .{
            clamp01(buffer[i][1]),
            clamp01(buffer[i + 1][1]),
            clamp01(buffer[i + 2][1]),
            clamp01(buffer[i + 3][1]),
        };
        g_vec = linearToSrgb4(g_vec);

        // Load and clamp B values
        var b_vec: @Vector(4, f32) = .{
            clamp01(buffer[i][2]),
            clamp01(buffer[i + 1][2]),
            clamp01(buffer[i + 2][2]),
            clamp01(buffer[i + 3][2]),
        };
        b_vec = linearToSrgb4(b_vec);

        // Write back
        buffer[i][0] = r_vec[0];
        buffer[i][1] = g_vec[0];
        buffer[i][2] = b_vec[0];

        buffer[i + 1][0] = r_vec[1];
        buffer[i + 1][1] = g_vec[1];
        buffer[i + 1][2] = b_vec[1];

        buffer[i + 2][0] = r_vec[2];
        buffer[i + 2][1] = g_vec[2];
        buffer[i + 2][2] = b_vec[2];

        buffer[i + 3][0] = r_vec[3];
        buffer[i + 3][1] = g_vec[3];
        buffer[i + 3][2] = b_vec[3];
    }

    // Scalar tail
    while (i < buffer.len) : (i += 1) {
        buffer[i][0] = linearToSrgb(clamp01(buffer[i][0]));
        buffer[i][1] = linearToSrgb(clamp01(buffer[i][1]));
        buffer[i][2] = linearToSrgb(clamp01(buffer[i][2]));
    }
}

/// Accurate x^(5/12) for sRGB gamma conversion.
/// Uses cbrt(x) * sqrt(sqrt(cbrt(x))) = cbrt(x)^(5/4) = x^(5/12).
fn pow512(x: f32) f32 {
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;

    const cbrt_x = cbrt(x);
    const fourth_root_cbrt = @sqrt(@sqrt(cbrt_x));
    return cbrt_x * fourth_root_cbrt;
}

/// SIMD 4-wide x^(5/12).
fn pow512Vec4(x: @Vector(4, f32)) @Vector(4, f32) {
    const zero: @Vector(4, f32) = @splat(0.0);
    const one: @Vector(4, f32) = @splat(1.0);

    const cbrt_x = cbrtVec4(x);
    const fourth_root_cbrt = @sqrt(@sqrt(cbrt_x));
    const result = cbrt_x * fourth_root_cbrt;

    // Clamp to [0, 1]
    return @min(@max(result, zero), one);
}

/// Fast cube root using Newton-Raphson with bit manipulation initial guess.
fn cbrt(x: f32) f32 {
    if (x == 0.0) return 0.0;

    const neg = x < 0.0;
    const abs_x = if (neg) -x else x;

    // Initial guess via bit hack
    var v: u32 = @bitCast(abs_x);
    v = v / 3 + 709921077;
    var y: f32 = @bitCast(v);

    // Three Newton-Raphson iterations for high accuracy
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;

    return if (neg) -y else y;
}

/// SIMD 4-wide cube root.
fn cbrtVec4(x: @Vector(4, f32)) @Vector(4, f32) {
    const zero: @Vector(4, f32) = @splat(0.0);
    const neg_mask = x < zero;
    const abs_x = @abs(x);

    // Initial guess via bit hack
    var v: @Vector(4, u32) = @bitCast(abs_x);
    const magic: @Vector(4, u32) = @splat(709921077);
    const three: @Vector(4, u32) = @splat(3);
    v = v / three + magic;
    var y: @Vector(4, f32) = @bitCast(v);

    // Three Newton-Raphson iterations
    const two: @Vector(4, f32) = @splat(2.0);
    const three_f: @Vector(4, f32) = @splat(3.0);
    y = (two * y + abs_x / (y * y)) / three_f;
    y = (two * y + abs_x / (y * y)) / three_f;
    y = (two * y + abs_x / (y * y)) / three_f;

    return @select(f32, neg_mask, -y, y);
}

inline fn clamp01(x: f32) f32 {
    return @min(@max(x, 0.0), 1.0);
}

test "srgb round-trip" {
    // Test round-trip: linear -> srgb -> linear should be approximately equal
    const test_values = [_]f32{ 0.0, 0.001, 0.01, 0.1, 0.5, 0.9, 1.0 };
    for (test_values) |linear| {
        const srgb = linearToSrgb(linear);
        const back = srgbToLinear(@intFromFloat(@min(@max(srgb * 255.0, 0), 255)));
        try std.testing.expectApproxEqAbs(linear, back, 0.01);
    }
}

test "gamma known values" {
    // Black and white should be unchanged
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), linearToSrgb(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), linearToSrgb(1.0), 0.001);

    // Mid-gray in linear (~0.214) should map to ~0.5 in sRGB
    const linear_mid = 0.214;
    const srgb_mid = linearToSrgb(linear_mid);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), srgb_mid, 0.02);
}
