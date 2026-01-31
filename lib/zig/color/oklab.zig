const std = @import("std");

const color = @import("color.zig");
const gamma = @import("gamma.zig");

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

    pub fn distanceSq(self: OkLab, other: OkLab, chroma_weight: f32) f32 {
        const d_l = self.l - other.l;
        const da = self.a - other.a;
        const db = self.b - other.b;
        const cw = @min(@max(chroma_weight, 0.5), 4.0);
        const l_weight = 2.0 / cw;
        return l_weight * d_l * d_l + cw * (da * da + db * db);
    }
};

pub fn srgbToOklab(r: u8, g: u8, b: u8) OkLab {
    const r_linear = gamma.srgbToLinear(r);
    const g_linear = gamma.srgbToLinear(g);
    const b_linear = gamma.srgbToLinear(b);
    return linearRgbToOklab(r_linear, g_linear, b_linear);
}

fn linearRgbToOklab(r: f32, g: f32, b: f32) OkLab {
    const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    const lp = gamma.cbrt(l);
    const mp = gamma.cbrt(m);
    const sp = gamma.cbrt(s);

    return .{
        .l = 0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
        .a = 1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
        .b = 0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp,
    };
}

fn oklabToLinearRgb(lab: OkLab) color.Color {
    const lp = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    const mp = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    const sp = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b;

    const l = lp * lp * lp;
    const m = mp * mp * mp;
    const s = sp * sp * sp;

    const r = @max(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, 0.0);
    const g = @max(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, 0.0);
    const b = @max(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s, 0.0);

    return color.rgb(r, g, b);
}
