const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Rainbow = @import("Rainbow.zig");
const Scene = @import("Scene.zig");
const util = @import("util.zig");

const Self = @This();

origin: @Vector(2, f32),
angle_start: f32,
angle_end: f32,
side: Scene.Side,

pub fn init(
    origin: @Vector(2, f32),
    first_end: @Vector(2, f32),
    last_end: @Vector(2, f32),
    side: Scene.Side,
) Self {
    const angle_first = angleOf(origin, first_end);
    const angle_last = angleOf(origin, last_end);
    const margin = edgeMargin(angle_first, angle_last);

    return .{
        .origin = origin,
        .angle_start = angle_first - margin,
        .angle_end = angle_last + margin,
        .side = side,
    };
}

pub fn render(
    self: Self,
    band: *Image.Band(Linear),
    viewport: Image.Viewport,
    scene: Scene,
    rainbow: Rainbow,
) void {
    const normalized_start = normalizeAngle(self.angle_start);
    const normalized_end = normalizeAngle(self.angle_end);

    var angle_diff = normalized_end - normalized_start;

    if (angle_diff > std.math.pi) angle_diff -= std.math.tau;
    if (angle_diff < -std.math.pi) angle_diff += std.math.tau;

    const angle_span = @abs(angle_diff);

    if (angle_span < 0.001 or angle_span > std.math.pi) return;

    const reverse = angle_diff < 0;
    const sorted_start = if (reverse) normalized_end else normalized_start;
    const sorted_end = if (reverse) normalized_start else normalized_end;
    const wrap_around = sorted_start > sorted_end;

    const angular_margin: f32 = 0.002;

    const sector_start = if (wrap_around)
        normalizeAngle(sorted_start - angular_margin)
    else
        @max(sorted_start - angular_margin, 0);

    const sector_end = if (wrap_around)
        normalizeAngle(sorted_end + angular_margin)
    else
        @min(sorted_end + angular_margin, std.math.tau - 0.0001);

    // Sector edge directions with epsilon margin for containment test
    const direction_start: @Vector(2, f32) = .{ @cos(sector_start), @sin(sector_start) };
    const direction_end: @Vector(2, f32) = .{ @cos(sector_end), @sin(sector_end) };

    // Exact edge directions for spectrum position interpolation
    const direction_start_exact: @Vector(2, f32) = .{ @cos(sorted_start), @sin(sorted_start) };
    const direction_end_exact: @Vector(2, f32) = .{ @cos(sorted_end), @sin(sorted_end) };

    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const normalized_bounds = switch (self.side) {
        .internal => scene.prism.bounds(),
        .external => scene.sectorBounds(sector_start, sector_end, wrap_around),
    };

    const min_pixel = viewport.toPixel(.{ normalized_bounds[0], normalized_bounds[1] });
    const max_pixel = viewport.toPixel(.{ normalized_bounds[2], normalized_bounds[3] });

    const x_min = util.floorClamped(min_pixel[0], band.width);
    const x_max = util.ceilClamped(max_pixel[0], band.width);
    const y_min = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_max = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    for (y_min..y_max) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_min..x_max) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            // Cross-product sector containment (cheapest test first)
            const dx = point[0] - self.origin[0];
            const dy = point[1] - self.origin[1];
            const cross_start = direction_start[0] * dy - direction_start[1] * dx;
            const cross_end = direction_end[0] * dy - direction_end[1] * dx;

            if (cross_start < 0 or cross_end > 0) continue;

            if (!scene.containsPoint(self.side, point)) continue;

            // Cross-product ratio for spectrum position (replaces atan2)
            const cross_start_exact = direction_start_exact[0] * dy - direction_start_exact[1] * dx;
            const cross_end_exact = direction_end_exact[0] * dy - direction_end_exact[1] * dx;
            const spectrum_position_raw = std.math.clamp(cross_start_exact / (cross_start_exact - cross_end_exact), 0, 1);

            const spectrum_position =
                if (reverse) 1.0 - spectrum_position_raw else spectrum_position_raw;

            const color = rainbow.interpolate(spectrum_position);
            const pixel = band.colorAt(x, local_y);

            pixel.vec = pixel.vec + color.vec;
        }
    }
}

fn angleOf(from: @Vector(2, f32), to: @Vector(2, f32)) f32 {
    const delta = to - from;

    return std.math.atan2(delta[1], delta[0]);
}

const edge_margin_factor: f32 = 0.5 / (@as(f32, @floatFromInt(Rainbow.color_count)) - 1.0);

fn edgeMargin(angle_first: f32, angle_last: f32) f32 {
    var span = angle_last - angle_first;

    if (span > std.math.pi) span -= std.math.tau;
    if (span < -std.math.pi) span += std.math.tau;

    return span * edge_margin_factor;
}

fn normalizeAngle(angle: f32) f32 {
    return @mod(angle, std.math.tau);
}
