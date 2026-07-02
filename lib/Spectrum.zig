const std = @import("std");

const Image = @import("Image.zig");
const intensity = @import("intensity.zig");
const Linear = @import("Linear.zig");
const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const util = @import("util.zig");
const vector = @import("vector.zig");

const Self = @This();

origin: @Vector(2, f32),
direction_start: @Vector(2, f32),
direction_end: @Vector(2, f32),
direction_start_exact: @Vector(2, f32),
direction_end_exact: @Vector(2, f32),
reverse: bool,

pub fn init(
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

    const ccw_earlier = if (reverse) direction_last else direction_first;
    const ccw_later = if (reverse) direction_first else direction_last;

    // Widen sector: rotate edges outward by the margin
    const start_exact = rotateBy(ccw_earlier, cos_margin, -sin_margin);
    const end_exact = rotateBy(ccw_later, cos_margin, sin_margin);

    const cos_epsilon = comptime @cos(@as(f32, 0.002));
    const sin_epsilon = comptime @sin(@as(f32, 0.002));

    return .{
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
    rainbow: Rainbow,
    attenuation_normalized_distance: f32,
    prism: Prism,
    prism_tint: Linear,
) void {
    // Skip degenerate sectors: near-zero span (directions identical) or
    // near-π span (directions antiparallel) where cross-product interpolation breaks down.
    const dot_exact = vector.dot(self.direction_start_exact, self.direction_end_exact);

    if (dot_exact > 0.9999 or dot_exact < -0.9999) return;

    const band_colors = rainbow.colors;

    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const normalized_bounds = sectorBounds(self.direction_start, self.direction_end);

    // Pad the bounding box one pixel so the angular feather at the fan edges is not
    // clipped where an edge grazes the box (notably the apex near the disc centre).
    const margin = viewport.inverse_scale;
    const pixel_a = viewport.toPixel(.{ normalized_bounds[0] - margin, normalized_bounds[1] - margin });
    const pixel_b = viewport.toPixel(.{ normalized_bounds[2] + margin, normalized_bounds[3] + margin });
    const min_pixel = @min(pixel_a, pixel_b);
    const max_pixel = @max(pixel_a, pixel_b);

    const x_min = util.floorClamped(min_pixel[0], band.width);
    const x_max = util.ceilClamped(max_pixel[0], band.width);
    const y_min = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_max = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    if (x_min >= x_max or y_min >= y_max) return;

    for (y_min..y_max) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_min..x_max) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            // Sector containment first (cheaper than the distance test). The cross
            // products are signed perpendicular distances to the sector's edge rays
            // (the directions are unit vectors), so they feed the coverage ramp directly.
            const dx = point[0] - self.origin[0];
            const dy = point[1] - self.origin[1];
            const cross_start = self.direction_start[0] * dy - self.direction_start[1] * dx;
            const cross_end = self.direction_end[0] * dy - self.direction_end[1] * dx;

            // Analytic antialiasing: feather both angular edges of the fan over one
            // pixel. The outer arc rides the disc rim and is left to Crop.
            const angular_coverage = util.edgeCoverage(cross_start, viewport.scale) *
                util.edgeCoverage(-cross_end, viewport.scale);

            if (angular_coverage <= 0.0) continue;

            const distance_squared = @reduce(.Add, point * point);

            if (distance_squared > 1.0) continue;

            const attenuation_distance =
                @max(attenuation_normalized_distance, std.math.floatEps(f32));

            // Fades out toward the centre of the disc.
            const attenuation_linear =
                std.math.clamp(@sqrt(distance_squared) / attenuation_distance, 0.0, 1.0);

            const attenuation_value =
                angular_coverage * intensity.falloff(1.0 - attenuation_linear);

            // Cross-product ratio gives angular position within the sector
            const cross_start_exact =
                self.direction_start_exact[0] * dy - self.direction_start_exact[1] * dx;

            const cross_end_exact =
                self.direction_end_exact[0] * dy - self.direction_end_exact[1] * dx;

            // Origin pixel: cross_start_exact == cross_end_exact == 0 → 0/0 = NaN, but
            // clamp() yields a finite value and attenuation_value == 0 here, so it adds nothing.
            const spectrum_position_raw =
                std.math.clamp(cross_start_exact / (cross_start_exact - cross_end_exact), 0, 1);

            const spectrum_position =
                if (self.reverse) 1.0 - spectrum_position_raw else spectrum_position_raw;

            // Inside the prism: one beam graded from white at the prism face to the
            // prism tint deeper in, like the input ray. Outside: solid colour bands.
            const color = if (prism.containsPoint(point))
                Linear.lerp(Linear.white, prism_tint, @sqrt(1.0 - attenuation_linear))
            else
                self.antialiasedBand(
                    &band_colors,
                    spectrum_position,
                    cross_start_exact,
                    cross_end_exact,
                    viewport.scale,
                );

            const pixel = band.colorAt(x, local_y);

            pixel.vec = pixel.vec + color.vec * @as(@Vector(4, f32), @splat(attenuation_value));
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

/// The solid colour for one pixel, with its band boundaries antialiased.
/// Away from a seam this is the plain band colour; within one pixel of a boundary it
/// blends the two neighbouring bands by analytic coverage. `spectrum_position` selects
/// the band; the exact cross products give the boundary's screen-space slope
/// (d position / d pixel) so the seam spans one pixel at any distance from the apex.
fn antialiasedBand(
    self: Self,
    band_colors: *const [Rainbow.color_count]Linear,
    spectrum_position: f32,
    cross_start_exact: f32,
    cross_end_exact: f32,
    pixels_per_unit: f32,
) Linear {
    const count: f32 = @floatFromInt(Rainbow.color_count);
    const scaled = spectrum_position * count;
    const boundary = @round(scaled);
    const boundary_index: usize = @intFromFloat(boundary);

    // The first and last half-bands run to the fan's outer angular edges, which
    // angular_coverage already feathers; only interior boundaries blend two bands.
    if (boundary_index == 0 or boundary_index >= Rainbow.color_count) {
        const index: usize = @intFromFloat(@min(@floor(scaled), count - 1.0));

        return band_colors[index];
    }

    const a = cross_start_exact;
    const b = cross_end_exact;
    const spread = a - b;

    // Near the apex spread -> 0 (and gradient_magnitude below with it), giving 0/0;
    // attenuation is 0 there so nothing shows. Bail early to keep the NaN out of the blend.
    if (spread <= std.math.floatEps(f32)) return band_colors[boundary_index];

    // position = a / (a - b), so its gradient is (-b*grad_a + a*grad_b) / (a - b)^2,
    // where grad_a, grad_b are the perpendiculars of the unit edge directions. Its
    // magnitude times inverse_scale is the position change per pixel.
    const gradient_x = b * self.direction_start_exact[1] - a * self.direction_end_exact[1];
    const gradient_y = a * self.direction_end_exact[0] - b * self.direction_start_exact[0];
    const gradient_magnitude = @sqrt(gradient_x * gradient_x + gradient_y * gradient_y);

    if (gradient_magnitude <= std.math.floatEps(f32)) return band_colors[boundary_index];

    // Signed pixel distance from the boundary toward increasing position; the upper
    // band (band_colors[boundary_index]) sits on the positive side.
    const signed_pixels =
        (spectrum_position - boundary / count) * spread * spread * pixels_per_unit / gradient_magnitude;

    const coverage = std.math.clamp(signed_pixels + 0.5, 0.0, 1.0);

    return Linear.lerp(band_colors[boundary_index - 1], band_colors[boundary_index], coverage);
}

test "render produces spectrum with rotated viewport" {
    const rainbow = Rainbow.dark_side_of_the_moon;
    const image = Image.init(48, 64);
    const viewport = image.viewportRotated(.clockwise_90);
    const pixel_count = 48 * 64;

    var buffer = [_]Linear{Linear.black} ** pixel_count;

    const band = try image.band(Linear, &buffer, 64, 0);
    const spectrum = Self.init(.{ 0, 0 }, .{ 0.8, 0.3 }, .{ 0.8, -0.3 });

    spectrum.render(band, viewport, rainbow, 0.5, Prism.init(0.8), Linear.white);

    var found_color = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > 0 or pixel.vec[1] > 0 or pixel.vec[2] > 0) {
            found_color = true;
            break;
        }
    }

    try std.testing.expect(found_color);
}

test "attenuation reduces brightness near origin" {
    const rainbow = Rainbow.dark_side_of_the_moon;
    const size = 200;
    const image = Image.init(size, size);
    const viewport = image.viewport();
    const pixel_count = size * size;
    const center = size / 2;

    var buffer = [_]Linear{Linear.black} ** pixel_count;

    const band = try image.band(Linear, &buffer, size, 0);

    const spectrum = Self.init(.{ 0, 0 }, .{ 1, 0.2 }, .{ 1, -0.2 });
    spectrum.render(band, viewport, rainbow, 0.5, Prism.init(0.8), Linear.white);

    // Sum across multiple rows to average out angular color differences.
    var near_sum: f64 = 0;
    var near_count: u32 = 0;
    var far_sum: f64 = 0;
    var far_count: u32 = 0;

    for (0..size) |y| {
        for (0..size) |x| {
            const pixel = buffer[y * size + x];
            const brightness = pixel.vec[0] + pixel.vec[1] + pixel.vec[2];

            if (brightness == 0) continue;

            const dx: f32 = (@as(f32, @floatFromInt(x)) + 0.5 - @as(f32, @floatFromInt(center))) /
                @as(f32, @floatFromInt(center));

            const dy: f32 = (@as(f32, @floatFromInt(y)) + 0.5 - @as(f32, @floatFromInt(center))) /
                @as(f32, @floatFromInt(center));

            const distance = @sqrt(dx * dx + dy * dy);

            if (distance >= 0.05 and distance < 0.15) {
                near_sum += brightness;
                near_count += 1;
            } else if (distance >= 0.50 and distance < 0.75) {
                far_sum += brightness;
                far_count += 1;
            }
        }
    }

    try std.testing.expect(near_count > 0);
    try std.testing.expect(far_count > 0);

    const near_avg = near_sum / @as(f64, @floatFromInt(near_count));
    const far_avg = far_sum / @as(f64, @floatFromInt(far_count));

    // Cubic attenuation makes the far zone much brighter than the near zone.
    try std.testing.expect(far_avg > near_avg * 3.0);
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

// The unit direction whose spectrum position is band_parameter / color_count: the
// projective coordinate of (color_count - t)*start + t*end works out to exactly t/N.
fn rayDirection(spectrum: Self, band_parameter: f32) @Vector(2, f32) {
    const count: f32 = @floatFromInt(Rainbow.color_count);
    const lower: @Vector(2, f32) = @splat(count - band_parameter);
    const upper: @Vector(2, f32) = @splat(band_parameter);

    return vector.normalize(lower * spectrum.direction_start_exact + upper * spectrum.direction_end_exact);
}

fn spectrumPositionAt(spectrum: Self, point: @Vector(2, f32)) struct {
    position: f32,
    cross_start: f32,
    cross_end: f32,
} {
    const dx = point[0] - spectrum.origin[0];
    const dy = point[1] - spectrum.origin[1];
    const cross_start = spectrum.direction_start_exact[0] * dy - spectrum.direction_start_exact[1] * dx;
    const cross_end = spectrum.direction_end_exact[0] * dy - spectrum.direction_end_exact[1] * dx;
    const raw = std.math.clamp(cross_start / (cross_start - cross_end), 0, 1);

    return .{
        .position = if (spectrum.reverse) 1.0 - raw else raw,
        .cross_start = cross_start,
        .cross_end = cross_end,
    };
}

test "antialiasedBand blends across a seam but stays solid within a band" {
    const rainbow = Rainbow.dark_side_of_the_moon;
    const band_colors = rainbow.colors;
    const scale: f32 = 100.0;
    const count: f32 = @floatFromInt(Rainbow.color_count);

    const spectrum = Self.init(.{ 0, 0 }, .{ 1, 0.25 }, .{ 1, -0.25 });

    // A point sitting on the seam of an interior band, well away from the apex, mixes
    // the two neighbouring bands about half and half.
    const on_seam = @as(@Vector(2, f32), @splat(0.6)) * rayDirection(spectrum, 3.0);
    const seam_sample = spectrumPositionAt(spectrum, on_seam);
    const seam_index: usize = @intFromFloat(@round(seam_sample.position * count));

    try std.testing.expect(seam_index >= 1 and seam_index < Rainbow.color_count);

    const blended = spectrum.antialiasedBand(
        &band_colors,
        seam_sample.position,
        seam_sample.cross_start,
        seam_sample.cross_end,
        scale,
    );

    inline for (0..3) |channel| {
        const midpoint =
            0.5 * (band_colors[seam_index - 1].vec[channel] + band_colors[seam_index].vec[channel]);

        try std.testing.expectApproxEqAbs(midpoint, blended.vec[channel], 0.02);
    }

    // A third of a band off the seam is many pixels away at this scale, so the blend
    // saturates back to the plain solid band colour.
    const in_band = @as(@Vector(2, f32), @splat(0.6)) * rayDirection(spectrum, 3.3);
    const deep_sample = spectrumPositionAt(spectrum, in_band);
    const deep_index: usize = @intFromFloat(@min(@floor(deep_sample.position * count), count - 1.0));

    const solid = spectrum.antialiasedBand(
        &band_colors,
        deep_sample.position,
        deep_sample.cross_start,
        deep_sample.cross_end,
        scale,
    );

    inline for (0..3) |channel| {
        try std.testing.expectApproxEqAbs(band_colors[deep_index].vec[channel], solid.vec[channel], 1e-6);
    }
}
