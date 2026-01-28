const std = @import("std");

const color = @import("color.zig");
const gamma = @import("gamma.zig");

/// OkLab perceptually uniform color space.
/// L: lightness (0.0 = black, 1.0 = white)
/// a: green-red axis
/// b: blue-yellow axis
pub const OkLab = struct {
    l: f32,
    a: f32,
    b: f32,

    pub fn fromLinearRgb(c: color.Color) OkLab {
        return linearRgbToOklab(c[0], c[1], c[2]);
    }

    pub fn toLinearRgb(self: OkLab) color.Color {
        return oklabToLinearRgb(self);
    }

    pub fn lerp(a_lab: OkLab, b_lab: OkLab, t: f32) OkLab {
        return .{
            .l = a_lab.l + t * (b_lab.l - a_lab.l),
            .a = a_lab.a + t * (b_lab.a - a_lab.a),
            .b = a_lab.b + t * (b_lab.b - a_lab.b),
        };
    }

    /// Compute chroma (saturation metric).
    pub fn chroma(self: OkLab) f32 {
        return @sqrt(self.a * self.a + self.b * self.b);
    }

    /// Weighted distance squared for palette matching.
    /// chroma_weight = 1.0: L weighted 2x (good for general images)
    /// chroma_weight = 2.0: Equal L and chroma weighting (better for rainbows)
    /// chroma_weight = 4.0: Chroma weighted 2x (strongly prioritizes hue matching)
    pub fn distanceSq(self: OkLab, other: OkLab, chroma_weight: f32) f32 {
        const d_l = self.l - other.l;
        const da = self.a - other.a;
        const db = self.b - other.b;
        // Clamp to valid range (0.5-4.0)
        const cw = @min(@max(chroma_weight, 0.5), 4.0);
        // Inverse relationship: as chroma_weight increases, l_weight decreases
        const l_weight = 2.0 / cw;
        return l_weight * d_l * d_l + cw * (da * da + db * db);
    }
};

/// SIMD 4-wide OkLab for batch processing.
pub const OkLab4 = struct {
    l: @Vector(4, f32),
    a: @Vector(4, f32),
    b: @Vector(4, f32),

    pub fn fromLinearRgb4(r: @Vector(4, f32), g: @Vector(4, f32), b: @Vector(4, f32)) OkLab4 {
        return linearRgbToOklab4(r, g, b);
    }

    pub fn toLinearRgb4(self: OkLab4) struct { r: @Vector(4, f32), g: @Vector(4, f32), b: @Vector(4, f32) } {
        return oklabToLinearRgb4(self);
    }
};

/// Convert sRGB byte values to OkLab.
pub fn srgbToOklab(r: u8, g: u8, b: u8) OkLab {
    const r_linear = gamma.srgbToLinear(r);
    const g_linear = gamma.srgbToLinear(g);
    const b_linear = gamma.srgbToLinear(b);
    return linearRgbToOklab(r_linear, g_linear, b_linear);
}

/// Convert linear RGB to OkLab.
fn linearRgbToOklab(r: f32, g: f32, b: f32) OkLab {
    // Linear RGB to LMS (cone responses)
    const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    // Cube root (perceptual nonlinearity)
    const lp = cbrt(l);
    const mp = cbrt(m);
    const sp = cbrt(s);

    // LMS' to OkLab
    return .{
        .l = 0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
        .a = 1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
        .b = 0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp,
    };
}

/// Convert OkLab to linear RGB.
fn oklabToLinearRgb(lab: OkLab) color.Color {
    // OkLab to LMS'
    const lp = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    const mp = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    const sp = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b;

    // Cube (inverse of cube root)
    const l = lp * lp * lp;
    const m = mp * mp * mp;
    const s = sp * sp * sp;

    // LMS to linear RGB
    var r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    var g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    var b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

    // Clamp to valid range
    r = @max(r, 0.0);
    g = @max(g, 0.0);
    b = @max(b, 0.0);

    return color.rgb(r, g, b);
}

/// SIMD 4-wide linear RGB to OkLab conversion.
fn linearRgbToOklab4(r: @Vector(4, f32), g: @Vector(4, f32), b: @Vector(4, f32)) OkLab4 {
    // Linear RGB to LMS (cone responses)
    const l = @as(@Vector(4, f32), @splat(0.4122214708)) * r +
        @as(@Vector(4, f32), @splat(0.5363325363)) * g +
        @as(@Vector(4, f32), @splat(0.0514459929)) * b;
    const m = @as(@Vector(4, f32), @splat(0.2119034982)) * r +
        @as(@Vector(4, f32), @splat(0.6806995451)) * g +
        @as(@Vector(4, f32), @splat(0.1073969566)) * b;
    const s = @as(@Vector(4, f32), @splat(0.0883024619)) * r +
        @as(@Vector(4, f32), @splat(0.2817188376)) * g +
        @as(@Vector(4, f32), @splat(0.6299787005)) * b;

    // Cube root (perceptual nonlinearity)
    const lp = cbrtVec4(l);
    const mp = cbrtVec4(m);
    const sp = cbrtVec4(s);

    // LMS' to OkLab
    return .{
        .l = @as(@Vector(4, f32), @splat(0.2104542553)) * lp +
            @as(@Vector(4, f32), @splat(0.7936177850)) * mp -
            @as(@Vector(4, f32), @splat(0.0040720468)) * sp,
        .a = @as(@Vector(4, f32), @splat(1.9779984951)) * lp -
            @as(@Vector(4, f32), @splat(2.4285922050)) * mp +
            @as(@Vector(4, f32), @splat(0.4505937099)) * sp,
        .b = @as(@Vector(4, f32), @splat(0.0259040371)) * lp +
            @as(@Vector(4, f32), @splat(0.7827717662)) * mp -
            @as(@Vector(4, f32), @splat(0.8086757660)) * sp,
    };
}

/// SIMD 4-wide OkLab to linear RGB conversion.
fn oklabToLinearRgb4(lab: OkLab4) struct { r: @Vector(4, f32), g: @Vector(4, f32), b: @Vector(4, f32) } {
    // OkLab to LMS'
    const lp = lab.l +
        @as(@Vector(4, f32), @splat(0.3963377774)) * lab.a +
        @as(@Vector(4, f32), @splat(0.2158037573)) * lab.b;
    const mp = lab.l -
        @as(@Vector(4, f32), @splat(0.1055613458)) * lab.a -
        @as(@Vector(4, f32), @splat(0.0638541728)) * lab.b;
    const sp = lab.l -
        @as(@Vector(4, f32), @splat(0.0894841775)) * lab.a -
        @as(@Vector(4, f32), @splat(1.2914855480)) * lab.b;

    // Cube (inverse of cube root)
    const l = lp * lp * lp;
    const m = mp * mp * mp;
    const s = sp * sp * sp;

    // LMS to linear RGB
    const zero: @Vector(4, f32) = @splat(0.0);
    const r = @max(@as(@Vector(4, f32), @splat(4.0767416621)) * l -
        @as(@Vector(4, f32), @splat(3.3077115913)) * m +
        @as(@Vector(4, f32), @splat(0.2309699292)) * s, zero);
    const g = @max(@as(@Vector(4, f32), @splat(-1.2684380046)) * l +
        @as(@Vector(4, f32), @splat(2.6097574011)) * m -
        @as(@Vector(4, f32), @splat(0.3413193965)) * s, zero);
    const b = @max(@as(@Vector(4, f32), @splat(-0.0041960863)) * l -
        @as(@Vector(4, f32), @splat(0.7034186147)) * m +
        @as(@Vector(4, f32), @splat(1.7076147010)) * s, zero);

    return .{ .r = r, .g = g, .b = b };
}

/// Scalar cube root using Newton-Raphson.
fn cbrt(x: f32) f32 {
    if (x == 0.0) return 0.0;

    const neg = x < 0.0;
    const abs_x = if (neg) -x else x;

    // Initial guess via bit hack
    var v: u32 = @bitCast(abs_x);
    v = v / 3 + 709921077;
    var y: f32 = @bitCast(v);

    // Three Newton-Raphson iterations
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

test "oklab round-trip" {
    const test_colors = [_]color.Color{
        color.rgb(0, 0, 0), // Black
        color.rgb(1, 1, 1), // White
        color.rgb(1, 0, 0), // Red
        color.rgb(0, 1, 0), // Green
        color.rgb(0, 0, 1), // Blue
        color.rgb(0.5, 0.5, 0.5), // Gray
    };

    for (test_colors) |c| {
        const lab = OkLab.fromLinearRgb(c);
        const back = lab.toLinearRgb();
        try std.testing.expectApproxEqAbs(c[0], back[0], 0.001);
        try std.testing.expectApproxEqAbs(c[1], back[1], 0.001);
        try std.testing.expectApproxEqAbs(c[2], back[2], 0.001);
    }
}

test "oklab known values" {
    // Black should have L=0
    const black = OkLab.fromLinearRgb(color.rgb(0, 0, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), black.l, 0.001);

    // White should have L=1, a=0, b=0
    const white = OkLab.fromLinearRgb(color.rgb(1, 1, 1));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), white.l, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), white.a, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), white.b, 0.01);
}

test "oklab lerp" {
    const black = OkLab.fromLinearRgb(color.rgb(0, 0, 0));
    const white = OkLab.fromLinearRgb(color.rgb(1, 1, 1));

    const mid = OkLab.lerp(black, white, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mid.l, 0.01);
}
