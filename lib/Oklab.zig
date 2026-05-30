const std = @import("std");

const Linear = @import("Linear.zig");

const Self = @This();

vec: @Vector(4, f32),

/// https://en.wikipedia.org/wiki/Linear_interpolation
pub fn lerp(a: Self, b: Self, t: f32) Self {
    std.debug.assert(t >= 0.0 and t <= 1.0);

    const t_vec: @Vector(4, f32) = @splat(t);

    return .{ .vec = a.vec + (b.vec - a.vec) * t_vec };
}

/// https://bottosson.github.io/posts/oklab/
pub fn toLinear(self: Self) Linear {
    const l = self.vec[0];
    const a = self.vec[1];
    const b = self.vec[2];

    // Oklab → LMS (cube roots)
    const lp = l + 0.3963377774 * a + 0.2158037573 * b;
    const mp = l - 0.1055613458 * a - 0.0638541728 * b;
    const sp = l - 0.0894841775 * a - 1.2914855480 * b;

    // LMS (cube roots) → LMS (cube)
    const l3 = lp * lp * lp;
    const m3 = mp * mp * mp;
    const s3 = sp * sp * sp;

    // LMS → Linear RGB
    return .{ .vec = .{
        @max(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3, 0.0),
        @max(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3, 0.0),
        @max(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3, 0.0),
        self.vec[3],
    } };
}

test "lerp at t=0 returns first color" {
    const a: Self = .{ .vec = .{ 0.5, 0.1, -0.1, 1.0 } };
    const b: Self = .{ .vec = .{ 0.8, -0.1, 0.2, 1.0 } };

    try std.testing.expectEqual(a.vec, lerp(a, b, 0.0).vec);
}

test "lerp at t=1 returns second color" {
    const a: Self = .{ .vec = .{ 0.5, 0.1, -0.1, 1.0 } };
    const b: Self = .{ .vec = .{ 0.8, -0.1, 0.2, 1.0 } };
    const result = lerp(a, b, 1.0);

    inline for (0..4) |i| {
        try std.testing.expectApproxEqAbs(b.vec[i], result.vec[i], 1e-6);
    }
}

test "round-trip Linear → Oklab → Linear preserves values" {
    const original = Linear.init(0.5, 0.25, 0.75, 1.0);
    const back = original.toOklab().toLinear();

    try std.testing.expectApproxEqAbs(original.vec[0], back.vec[0], 1e-5);
    try std.testing.expectApproxEqAbs(original.vec[1], back.vec[1], 1e-5);
    try std.testing.expectApproxEqAbs(original.vec[2], back.vec[2], 1e-5);
    try std.testing.expectApproxEqAbs(original.vec[3], back.vec[3], 1e-5);
}
