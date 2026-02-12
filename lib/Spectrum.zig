const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const util = @import("util.zig");
const vector = @import("vector.zig");

const Self = @This();

region: Region,
origin: @Vector(2, f32),
direction_start: @Vector(2, f32),
direction_end: @Vector(2, f32),
direction_start_exact: @Vector(2, f32),
direction_end_exact: @Vector(2, f32),
reverse: bool,

pub const Region = enum { internal, external };

pub fn init(
    region: Region,
    origin: @Vector(2, f32),
    first_end: @Vector(2, f32),
    last_end: @Vector(2, f32),
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
        .region = region,
        .origin = origin,
        .direction_start = rotateBy(start_exact, cos_epsilon, -sin_epsilon),
        .direction_end = rotateBy(end_exact, cos_epsilon, sin_epsilon),
        .direction_start_exact = start_exact,
        .direction_end_exact = end_exact,
        .reverse = reverse,
    };
}

pub fn render(
    self: Self,
    band: Image.Band(Linear),
    viewport: anytype,
    prism: Prism,
    rainbow: Rainbow,
) void {
    // Skip degenerate sectors: near-zero span (directions identical) or
    // near-π span (directions antiparallel) where cross-product interpolation breaks down.
    const dot_exact = vector.dot(self.direction_start_exact, self.direction_end_exact);

    if (dot_exact > 0.9999 or dot_exact < -0.9999) return;

    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const normalized_bounds = if (self.region == .internal)
        prism.bounds()
    else
        sectorBounds(self.direction_start, self.direction_end);

    const pixel_a = viewport.toPixel(.{ normalized_bounds[0], normalized_bounds[1] });
    const pixel_b = viewport.toPixel(.{ normalized_bounds[2], normalized_bounds[3] });
    const min_pixel = @min(pixel_a, pixel_b);
    const max_pixel = @max(pixel_a, pixel_b);

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

            if (self.region == .internal) {
                if (!prism.containsPoint(point)) continue;
            } else {
                if (@reduce(.Add, point * point) > 1.0 or prism.containsPoint(point)) continue;
            }

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

fn sectorBounds(
    direction_start: @Vector(2, f32),
    direction_end: @Vector(2, f32),
) @Vector(4, f32) {
    const origin: @Vector(2, f32) = .{ 0, 0 };

    var bounds_min = @min(origin, @min(direction_start, direction_end));
    var bounds_max = @max(origin, @max(direction_start, direction_end));

    const cardinals = [_]@Vector(2, f32){
        .{ 1, 0 },
        .{ 0, 1 },
        .{ -1, 0 },
        .{ 0, -1 },
    };

    inline for (cardinals) |cardinal| {
        if (directionInSector(cardinal, direction_start, direction_end)) {
            bounds_min = @min(bounds_min, cardinal);
            bounds_max = @max(bounds_max, cardinal);
        }
    }

    return .{ bounds_min[0], bounds_min[1], bounds_max[0], bounds_max[1] };
}

/// Tests if a direction lies within the CCW sector from start to end (span <= π).
fn directionInSector(
    direction: @Vector(2, f32),
    sector_start: @Vector(2, f32),
    sector_end: @Vector(2, f32),
) bool {
    return vector.cross2d(sector_start, direction) >= 0 and
        vector.cross2d(direction, sector_end) >= 0;
}

test "render produces spectrum with rotated viewport" {
    const prism = Prism.init(0.8);
    const rainbow = Rainbow.get(.spectral);
    const image = Image.init(48, 64);
    const viewport = image.viewportRotated(.clockwise_90);
    const pixel_count = 48 * 64;

    var buffer = [_]Linear{Linear.black} ** pixel_count;

    const band = image.band(Linear, &buffer, 64, 0) catch unreachable;
    const spectrum = Self.init(.external, .{ 0, 0 }, .{ 0.8, 0.3 }, .{ 0.8, -0.3 });

    spectrum.render(band, viewport, prism, rainbow);

    var found_color = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > 0 or pixel.vec[1] > 0 or pixel.vec[2] > 0) {
            found_color = true;
            break;
        }
    }

    try std.testing.expect(found_color);
}

test "sectorBounds first quadrant" {
    const bounds = sectorBounds(.{ 1, 0 }, .{ 0, 1 });

    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[3], vector.tolerance);
}

test "sectorBounds third quadrant" {
    const bounds = sectorBounds(.{ -1, 0 }, .{ 0, -1 });

    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[3], vector.tolerance);
}

test "sectorBounds wrap-around" {
    const bounds = sectorBounds(.{ 0, -1 }, .{ 0, 1 });

    try std.testing.expectApproxEqAbs(@as(f32, 0), bounds[0], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bounds[1], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[2], vector.tolerance);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bounds[3], vector.tolerance);
}
