pub fn dot(a: @Vector(2, f32), b: @Vector(2, f32)) f32 {
    return @reduce(.Add, a * b);
}

pub fn lengthSq(v: @Vector(2, f32)) f32 {
    return dot(v, v);
}

pub fn length(v: @Vector(2, f32)) f32 {
    return @sqrt(lengthSq(v));
}

pub const tolerance: f32 = 1e-5;

pub fn normalize(v: @Vector(2, f32)) @Vector(2, f32) {
    const len = length(v);

    if (len < tolerance) return .{ 0, 0 };

    return v / @as(@Vector(2, f32), @splat(len));
}

/// 2D cross product: gives signed area of parallelogram formed by the two vectors.
pub fn cross2d(a: @Vector(2, f32), b: @Vector(2, f32)) f32 {
    return a[0] * b[1] - a[1] * b[0];
}

/// Returns true if the vector has unit length (with floating point tolerance).
pub fn isNormalized(v: @Vector(2, f32)) bool {
    return @abs(length(v) - 1.0) < tolerance;
}
