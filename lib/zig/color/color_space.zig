const std = @import("std");

const Vec4 = @Vector(4, f32);

pub const Linear = struct {
    vec: Vec4,

    pub const black: Linear = .{ .vec = .{ 0, 0, 0, 1 } };
    pub const white: Linear = .{ .vec = .{ 1, 1, 1, 1 } };

    pub inline fn init(r: f32, g: f32, b: f32, a: f32) Linear {
        return .{ .vec = .{ r, g, b, a } };
    }

    pub inline fn toOklab(self: Linear) Oklab {
        const r = self.vec[0];
        const g = self.vec[1];
        const b = self.vec[2];

        const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
        const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
        const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

        const lp = cbrt(l);
        const mp = cbrt(m);
        const sp = cbrt(s);

        return .{ .vec = .{
            0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
            1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
            0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp,
            self.vec[3],
        } };
    }

    pub inline fn toSrgba(self: Linear) Srgba {
        return .{
            .r = linearToSrgbByte(self.vec[0]),
            .g = linearToSrgbByte(self.vec[1]),
            .b = linearToSrgbByte(self.vec[2]),
            .a = @intFromFloat(std.math.clamp(self.vec[3], 0.0, 1.0) * 255.0),
        };
    }

    pub fn toSrgbaSlice(linear_colors: []const Linear, srgba_colors: []Srgba) void {
        for (linear_colors, srgba_colors) |linear, *srgba| {
            srgba.* = linear.toSrgba();
        }
    }

    pub inline fn lerp(a: Linear, b: Linear, t: f32) Linear {
        const t_vec: Vec4 = @splat(t);
        return .{ .vec = a.vec + (b.vec - a.vec) * t_vec };
    }
};

pub const Oklab = struct {
    vec: Vec4,

    pub inline fn init(l: f32, a_axis: f32, b_axis: f32, alpha: f32) Oklab {
        return .{ .vec = .{ l, a_axis, b_axis, alpha } };
    }

    pub inline fn toLinear(self: Oklab) Linear {
        const lp = self.vec[0] + 0.3963377774 * self.vec[1] + 0.2158037573 * self.vec[2];
        const mp = self.vec[0] - 0.1055613458 * self.vec[1] - 0.0638541728 * self.vec[2];
        const sp = self.vec[0] - 0.0894841775 * self.vec[1] - 1.2914855480 * self.vec[2];

        const l = lp * lp * lp;
        const m = mp * mp * mp;
        const s = sp * sp * sp;

        return .{ .vec = .{
            @max(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, 0.0),
            @max(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, 0.0),
            @max(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s, 0.0),
            self.vec[3],
        } };
    }

    pub inline fn lerp(a: Oklab, b: Oklab, t: f32) Oklab {
        const t_vec: Vec4 = @splat(t);
        return .{ .vec = a.vec + (b.vec - a.vec) * t_vec };
    }

    pub inline fn distanceSq(self: Oklab, other: Oklab, chroma_weight: f32) f32 {
        const d_l = self.vec[0] - other.vec[0];
        const da = self.vec[1] - other.vec[1];
        const db = self.vec[2] - other.vec[2];
        const cw = std.math.clamp(chroma_weight, 0.5, 4.0);
        const l_weight = 2.0 / cw;
        return l_weight * d_l * d_l + cw * (da * da + db * db);
    }
};

pub const Srgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub inline fn toLinear(self: Srgba) Linear {
        return .{ .vec = .{
            srgbByteToLinear(self.r),
            srgbByteToLinear(self.g),
            srgbByteToLinear(self.b),
            @as(f32, @floatFromInt(self.a)) / 255.0,
        } };
    }

    pub inline fn toOklab(self: Srgba) Oklab {
        return self.toLinear().toOklab();
    }
};

fn srgbByteToLinear(srgb: u8) f32 {
    const s = @as(f32, @floatFromInt(srgb)) / 255.0;
    if (s <= 0.04045) {
        return s / 12.92;
    }
    return std.math.pow(f32, (s + 0.055) / 1.055, 2.4);
}

fn linearToSrgbComponent(linear: f32) f32 {
    if (linear <= 0.0031308) {
        return linear * 12.92;
    }
    return 1.055 * pow512(linear) - 0.055;
}

fn linearToSrgbByte(linear: f32) u8 {
    const clamped = std.math.clamp(linear, 0.0, 1.0);
    return @intFromFloat(@round(linearToSrgbComponent(clamped) * 255.0));
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
    const v: u32 = @as(u32, @bitCast(abs_x)) / 3 + 709921077;
    var y: f32 = @bitCast(v);
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    y = (2.0 * y + abs_x / (y * y)) / 3.0;
    return std.math.copysign(y, x);
}
