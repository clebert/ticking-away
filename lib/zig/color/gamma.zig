const std = @import("std");

const color = @import("color.zig");

pub fn srgbToLinear(srgb: u8) f32 {
    const s = @as(f32, @floatFromInt(srgb)) / 255.0;
    if (s <= 0.04045) {
        return s / 12.92;
    }
    return std.math.pow(f32, (s + 0.055) / 1.055, 2.4);
}

pub fn linearToSrgb(linear: f32) f32 {
    if (linear <= 0.0031308) {
        return linear * 12.92;
    }
    return 1.055 * pow512(linear) - 0.055;
}

pub fn applyToBuffer(buffer: []color.Color) void {
    for (buffer) |*c| {
        c.*[0] = linearToSrgb(std.math.clamp(c.*[0], 0.0, 1.0));
        c.*[1] = linearToSrgb(std.math.clamp(c.*[1], 0.0, 1.0));
        c.*[2] = linearToSrgb(std.math.clamp(c.*[2], 0.0, 1.0));
    }
}

fn pow512(x: f32) f32 {
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;

    const cbrt_x = cbrt(x);
    const fourth_root_cbrt = @sqrt(@sqrt(cbrt_x));
    return cbrt_x * fourth_root_cbrt;
}

pub fn cbrt(x: f32) f32 {
    if (x == 0.0) return 0.0;

    const abs_x = @abs(x);

    const v: u32 = @as(u32, @bitCast(abs_x)) / 3 + 709921077;
    var y: f32 = @bitCast(v);

    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;

    return std.math.copysign(y, x);
}

test "srgb round-trip" {
    const test_values = [_]f32{ 0.0, 0.001, 0.01, 0.1, 0.5, 0.9, 1.0 };
    for (test_values) |linear| {
        const srgb = linearToSrgb(linear);
        const back = srgbToLinear(@intFromFloat(@min(@max(srgb * 255.0, 0), 255)));
        try std.testing.expectApproxEqAbs(linear, back, 0.01);
    }
}

test "gamma known values" {
    try std.testing.expectApproxEqAbs(linearToSrgb(0.0), 0.0, 0.001);
    try std.testing.expectApproxEqAbs(linearToSrgb(1.0), 1.0, 0.001);

    const linear_mid = 0.214;
    const srgb_mid = linearToSrgb(linear_mid);
    try std.testing.expectApproxEqAbs(srgb_mid, 0.5, 0.02);
}
