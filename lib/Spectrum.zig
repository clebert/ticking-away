const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Rainbow = @import("Rainbow.zig");
const Scene = @import("Scene.zig");
const util = @import("util.zig");
const vector = @import("vector.zig");

const Self = @This();

origin: @Vector(2, f32),
direction_start: @Vector(2, f32),
direction_end: @Vector(2, f32),
direction_start_exact: @Vector(2, f32),
direction_end_exact: @Vector(2, f32),
reverse: bool,
side: Scene.Side,

pub fn init(
    origin: @Vector(2, f32),
    first_end: @Vector(2, f32),
    last_end: @Vector(2, f32),
    side: Scene.Side,
) Self {
    const direction_first = vector.normalize(first_end - origin);
    const direction_last = vector.normalize(last_end - origin);

    const cross = vector.cross2d(direction_first, direction_last);
    const span = std.math.atan2(cross, vector.dot(direction_first, direction_last));

    const abs_margin = @abs(span) * edge_margin_factor;
    const cos_margin = @cos(abs_margin);
    const sin_margin = @sin(abs_margin);

    const reverse = span < 0;

    // Sort by CCW order: start is CCW-earlier, end is CCW-later
    const ccw_earlier = if (reverse) direction_last else direction_first;
    const ccw_later = if (reverse) direction_first else direction_last;

    // Apply edge margin: widen sector by rotating edges outward
    const start_exact = rotateBy(ccw_earlier, cos_margin, -sin_margin);
    const end_exact = rotateBy(ccw_later, cos_margin, sin_margin);

    // Apply angular epsilon for containment test
    const cos_epsilon = comptime @cos(@as(f32, 0.002));
    const sin_epsilon = comptime @sin(@as(f32, 0.002));

    return .{
        .origin = origin,
        .direction_start = rotateBy(start_exact, cos_epsilon, -sin_epsilon),
        .direction_end = rotateBy(end_exact, cos_epsilon, sin_epsilon),
        .direction_start_exact = start_exact,
        .direction_end_exact = end_exact,
        .reverse = reverse,
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
    // Skip degenerate sectors: near-zero span (directions identical) or
    // near-π span (directions antiparallel) where cross-product interpolation breaks down.
    const dot_exact = vector.dot(self.direction_start_exact, self.direction_end_exact);

    if (dot_exact > 0.9999 or dot_exact < -0.9999) return;

    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const normalized_bounds = switch (self.side) {
        .internal => scene.prism.bounds(),
        .external => scene.sectorBounds(self.direction_start, self.direction_end),
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
            const cross_start = self.direction_start[0] * dy - self.direction_start[1] * dx;
            const cross_end = self.direction_end[0] * dy - self.direction_end[1] * dx;

            if (cross_start < 0 or cross_end > 0) continue;

            if (!scene.containsPoint(self.side, point)) continue;

            // Cross-product ratio for spectrum position (replaces atan2)
            const cross_start_exact = self.direction_start_exact[0] * dy - self.direction_start_exact[1] * dx;
            const cross_end_exact = self.direction_end_exact[0] * dy - self.direction_end_exact[1] * dx;
            const spectrum_position_raw = std.math.clamp(cross_start_exact / (cross_start_exact - cross_end_exact), 0, 1);

            const spectrum_position =
                if (self.reverse) 1.0 - spectrum_position_raw else spectrum_position_raw;

            const color = rainbow.interpolate(spectrum_position);
            const pixel = band.colorAt(x, local_y);

            pixel.vec = pixel.vec + color.vec;
        }
    }
}

const edge_margin_factor: f32 = 0.5 / (@as(f32, @floatFromInt(Rainbow.color_count)) - 1.0);

fn rotateBy(direction: @Vector(2, f32), cos_angle: f32, sin_angle: f32) @Vector(2, f32) {
    return .{
        direction[0] * cos_angle - direction[1] * sin_angle,
        direction[0] * sin_angle + direction[1] * cos_angle,
    };
}
