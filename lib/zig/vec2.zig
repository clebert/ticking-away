pub const Vec2 = @Vector(2, f32);

pub inline fn xy(x: f32, y: f32) Vec2 {
    return .{ x, y };
}

pub inline fn dot(a: Vec2, b: Vec2) f32 {
    return @reduce(.Add, a * b);
}

pub inline fn lengthSq(v: Vec2) f32 {
    return dot(v, v);
}

pub inline fn length(v: Vec2) f32 {
    return @sqrt(lengthSq(v));
}

pub inline fn normalize(v: Vec2) Vec2 {
    const len = length(v);
    if (len < 1e-9) return xy(0, 0);
    return v / @as(Vec2, @splat(len));
}
