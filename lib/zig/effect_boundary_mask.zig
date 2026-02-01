const boundary = @import("boundary.zig");
const color_space = @import("color_space.zig");
const frame = @import("frame.zig");

pub fn apply(
    band_srgba: *frame.BandSrgba,
    bnd: boundary.Boundary,
    fill_color: color_space.Srgba,
) void {
    const band_geometry = band_srgba.geometry;
    const width_i: i32 = @intCast(band_geometry.width);

    for (0..band_geometry.height) |local_y| {
        const global_y = band_geometry.globalY(local_y);
        const py = @as(f32, @floatFromInt(global_y)) + 0.5;

        if (bnd.scanlineRange(py)) |range| {
            const x_left: usize = @intCast(@max(0, @as(i32, @intFromFloat(@round(range.x_min)))));
            const x_right: usize = @intCast(@min(width_i, @as(i32, @intFromFloat(@round(range.x_max)))));

            fillRow(band_srgba, local_y, 0, x_left, fill_color);
            fillRow(band_srgba, local_y, x_right, band_geometry.width, fill_color);
        } else {
            fillRow(band_srgba, local_y, 0, band_geometry.width, fill_color);
        }
    }
}

fn fillRow(
    band_srgba: *frame.BandSrgba,
    local_y: usize,
    x_start: usize,
    x_end: usize,
    fill_color: color_space.Srgba,
) void {
    for (x_start..x_end) |x| {
        band_srgba.colorAt(x, local_y).* = .{
            .r = fill_color.r,
            .g = fill_color.g,
            .b = fill_color.b,
            .a = 255,
        };
    }
}
