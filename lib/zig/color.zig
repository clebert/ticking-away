pub const Color = @Vector(4, f32);

pub inline fn rgb(r: f32, g: f32, b: f32) Color {
    return .{ r, g, b, 1 };
}

pub inline fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
    return .{ r, g, b, a };
}

pub const black: Color = rgb(0, 0, 0);
pub const white: Color = rgb(1, 1, 1);
