const std = @import("std");

const Image = @import("Image.zig");
const intensity = @import("intensity.zig");
const Linear = @import("Linear.zig");
const Prism = @import("Prism.zig");
const Segment = @import("Segment.zig");
const util = @import("util.zig");

const Self = @This();

normalized_width: f32,
color: Linear,

pub fn renderLine(
    self: Self,
    band: Image.Band(Linear),
    viewport: anytype,
    line: Segment,
    attenuation_normalized_distance: f32,
    prism_tint: Linear,
) void {
    std.debug.assert(self.normalized_width >= 0.0 and self.normalized_width <= 1.0);

    // A zero-width glow draws nothing; returning early keeps the coverage ramp below
    // from dividing by normalized_width.
    if (self.normalized_width == 0.0) return;

    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    // Pad the bounding box one pixel beyond the glow width so the antialiased feather
    // at the capsule boundary is not clipped.
    const pad: @Vector(2, f32) = @splat(self.normalized_width + viewport.inverse_scale);
    const pixel_a = viewport.toPixel(@min(line.start, line.end) - pad);
    const pixel_b = viewport.toPixel(@max(line.start, line.end) + pad);
    const min_pixel = @min(pixel_a, pixel_b);
    const max_pixel = @max(pixel_a, pixel_b);

    const x_start = util.floorClamped(min_pixel[0], band.width);
    const x_end = util.ceilClamped(max_pixel[0], band.width);
    const y_start = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_end = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    // Guard: on ARM ReleaseFast, for(a..b) compiles as do-while that runs
    // ~4 billion iterations when a >= b. Bounds can be equal when the
    // bounding box falls entirely outside the band.
    if (x_start >= x_end or y_start >= y_end) return;

    // Full brightness up to normalized_distance, then fades to zero at the endpoint.
    const attenuation_length = @max(1.0 - attenuation_normalized_distance, std.math.floatEps(f32));

    for (y_start..y_end) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_start..x_end) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            if (@reduce(.Add, point * point) > 1.0) continue;

            const projection = line.project(point);
            const distance = @sqrt(projection.distance_squared);

            // Analytic antialiasing: feather the capsule's width boundary and rounded
            // caps over one pixel instead of a hard inside/outside cutoff.
            const edge_coverage = util.edgeCoverage(self.normalized_width - distance, viewport.scale);

            if (edge_coverage <= 0.0) continue;

            const attenuation_proximity = std.math.clamp(
                1.0 - (projection.normalized_position - attenuation_normalized_distance) / attenuation_length,
                0.0,
                1.0,
            );

            // Fades out toward the centre along the ray and stays flat across the beam
            // width, keeping the beam crisp.
            const brightness = edge_coverage * intensity.falloff(1.0 - attenuation_proximity);

            // Grade from self.color toward the prism tint as the ray runs deeper past
            // the prism face (self.color at the rim, where attenuation_proximity == 1).
            const color = Linear.lerp(self.color, prism_tint, @sqrt(1.0 - attenuation_proximity));

            const pixel = band.colorAt(x, local_y);
            const contribution = color.vec * @as(@Vector(4, f32), @splat(brightness));

            pixel.vec = @max(pixel.vec, contribution);
        }
    }
}

pub fn renderPrismEdges(
    self: Self,
    band: Image.Band(Linear),
    viewport: anytype,
    prism: Prism,
) void {
    std.debug.assert(self.normalized_width >= 0.0 and self.normalized_width <= 1.0);

    // A zero-width glow draws nothing; returning early avoids dividing by normalized_width below.
    if (self.normalized_width == 0.0) return;

    // The prism edge reads as a soft, slightly cool highlight that grades into
    // the tint deeper in, like the cover. The exponent keeps the highlight to a
    // thin band right at the rim.
    const rim_highlight = Linear.init(0.80, 0.84, 0.90, 1.0);
    const rim_falloff_exponent = 0.22;

    const width = self.normalized_width;
    const width_squared = width * width;
    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    // Pad the bounding box one pixel so the silhouette feather just outside the prism
    // edges is not clipped.
    const prism_bounds = prism.bounds();
    const margin = viewport.inverse_scale;
    const pixel_a = viewport.toPixel(.{ prism_bounds[0] - margin, prism_bounds[1] - margin });
    const pixel_b = viewport.toPixel(.{ prism_bounds[2] + margin, prism_bounds[3] + margin });
    const min_pixel = @min(pixel_a, pixel_b);
    const max_pixel = @max(pixel_a, pixel_b);

    const x_start = util.floorClamped(min_pixel[0], band.width);
    const x_end = util.ceilClamped(max_pixel[0], band.width);
    const y_start = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_end = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    if (x_start >= x_end or y_start >= y_end) return;

    for (y_start..y_end) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_start..x_end) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            const projection_right = prism.edges.get(.right).project(point);
            const projection_bottom = prism.edges.get(.bottom).project(point);
            const projection_left = prism.edges.get(.left).project(point);

            const min_distance_squared = @min(
                projection_right.distance_squared,
                @min(projection_bottom.distance_squared, projection_left.distance_squared),
            );

            if (min_distance_squared >= width_squared) continue;

            // Analytic antialiasing: the glow peaks right at the prism edge, so feather the
            // silhouette over one pixel using the signed distance to the boundary (positive
            // inside) rather than a hard containsPoint cutoff.
            const boundary_distance = @sqrt(min_distance_squared);
            const signed_distance =
                if (prism.containsPoint(point)) boundary_distance else -boundary_distance;
            const silhouette_coverage = util.edgeCoverage(signed_distance, viewport.scale);

            if (silhouette_coverage <= 0.0) continue;

            // Sum each edge's glow rather than taking only the nearest one:
            // where two edges meet at a corner their fields overlap and add, so
            // the tint stays continuous through the vertex with no dark seam
            // along the bisector — and still tapers to a point.
            var contribution = @as(@Vector(4, f32), @splat(0.0));

            for ([_]f32{
                projection_right.distance_squared,
                projection_bottom.distance_squared,
                projection_left.distance_squared,
            }) |distance_squared| {
                if (distance_squared >= width_squared) continue;

                const normalized_distance = @sqrt(distance_squared) / width;
                const brightness = intensity.falloff(normalized_distance);
                const edge_color = Linear.lerp(
                    rim_highlight,
                    self.color,
                    std.math.pow(f32, normalized_distance, rim_falloff_exponent),
                );

                contribution += edge_color.vec * @as(@Vector(4, f32), @splat(brightness));
            }

            const pixel = band.colorAt(x, local_y);
            pixel.vec = pixel.vec + contribution * @as(@Vector(4, f32), @splat(silhouette_coverage));
        }
    }
}

test "renderLine attenuation reduces brightness past normalized_distance" {
    const size = 200;
    const image = Image.init(size, size);
    const viewport = image.viewport();
    const pixel_count = size * size;
    const center = size / 2;

    var buffer = [_]Linear{Linear.black} ** pixel_count;

    const band = try image.band(Linear, &buffer, size, 0);
    const glow = Self{ .normalized_width = 0.1, .color = Linear.white };

    const line = Segment{ .start = .{ -1, 0 }, .end = .{ 0, 0 } };

    glow.renderLine(band, viewport, line, 0.4, Linear.white);

    var bright_sum: f64 = 0;
    var bright_count: u32 = 0;
    var dim_sum: f64 = 0;
    var dim_count: u32 = 0;

    for (0..size) |x| {
        const pixel = buffer[center * size + x];
        const brightness = pixel.vec[0];

        if (brightness == 0) continue;

        const position = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(center));

        if (position >= 0.1 and position < 0.3) {
            bright_sum += brightness;
            bright_count += 1;
        } else if (position >= 0.6 and position < 0.9) {
            dim_sum += brightness;
            dim_count += 1;
        }
    }

    try std.testing.expect(bright_count > 0);
    try std.testing.expect(dim_count > 0);

    const bright_avg = bright_sum / @as(f64, @floatFromInt(bright_count));
    const dim_avg = dim_sum / @as(f64, @floatFromInt(dim_count));

    try std.testing.expect(bright_avg > dim_avg * 3.0);
}

test "renderLine feathers the beam edge with partial coverage" {
    const size = 200;
    const image = Image.init(size, size);
    const viewport = image.viewport();

    var buffer = [_]Linear{Linear.black} ** (size * size);
    const band = try image.band(Linear, &buffer, size, 0);

    // A diagonal beam crosses the pixel grid at every sub-pixel offset, so its
    // feathered edge must leave pixels lit strictly between black and the beam's peak —
    // something a hard inside/outside cutoff cannot produce.
    const glow = Self{ .normalized_width = 0.05, .color = Linear.white };
    const line = Segment{ .start = .{ -0.5, -0.3 }, .end = .{ 0.5, 0.3 } };

    glow.renderLine(band, viewport, line, 0.0, Linear.white);

    var peak: f32 = 0;

    for (&buffer) |pixel| peak = @max(peak, pixel.vec[0]);

    try std.testing.expect(peak > 0);

    var found_partial = false;

    for (&buffer) |pixel| {
        const value = pixel.vec[0];

        if (value > 0.05 * peak and value < 0.95 * peak) {
            found_partial = true;
            break;
        }
    }

    try std.testing.expect(found_partial);
}

test "renderPrismEdges produces glow inside prism" {
    const prism = Prism.init(0.8);
    const image_size = 64;
    const image = Image.init(image_size, image_size);
    const viewport = image.viewport();

    var buffer = [_]Linear{Linear.black} ** (image_size * image_size);

    const band = try image.band(Linear, &buffer, image_size, 0);
    const glow = Self{ .normalized_width = 0.15, .color = Linear.white };

    glow.renderPrismEdges(band, viewport, prism);

    var found_glow = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > 0) {
            found_glow = true;
            break;
        }
    }

    try std.testing.expect(found_glow);
}

test "renderPrismEdges produces glow with rotated viewport" {
    const prism = Prism.init(0.8);
    const image = Image.init(48, 64);
    const viewport = image.viewportRotated(.clockwise_90);
    const pixel_count = 48 * 64;

    var buffer = [_]Linear{Linear.black} ** pixel_count;

    const band = try image.band(Linear, &buffer, 64, 0);
    const glow = Self{ .normalized_width = 0.15, .color = Linear.white };

    glow.renderPrismEdges(band, viewport, prism);

    var found_glow = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > 0) {
            found_glow = true;
            break;
        }
    }

    try std.testing.expect(found_glow);
}

test "renderPrismEdges does not write outside prism" {
    const prism = Prism.init(0.8);
    const image_size = 64;
    const image = Image.init(image_size, image_size);
    const viewport = image.viewport();

    var buffer = [_]Linear{Linear.black} ** (image_size * image_size);

    const band = try image.band(Linear, &buffer, image_size, 0);
    const glow = Self{ .normalized_width = 0.15, .color = Linear.white };

    glow.renderPrismEdges(band, viewport, prism);

    try std.testing.expectEqual(Linear.black.vec, buffer[0].vec);
    try std.testing.expectEqual(Linear.black.vec, buffer[image_size * image_size - 1].vec);
}

test "renderPrismEdges uses additive blending" {
    const prism = Prism.init(0.8);
    const image_size = 64;
    const image = Image.init(image_size, image_size);
    const viewport = image.viewport();
    const base = Linear.init(0.1, 0.1, 0.1, 1.0);

    var buffer = [_]Linear{base} ** (image_size * image_size);

    const band = try image.band(Linear, &buffer, image_size, 0);
    const glow = Self{ .normalized_width = 0.15, .color = Linear.white };

    glow.renderPrismEdges(band, viewport, prism);

    var found_additive = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > base.vec[0] + 0.01) {
            found_additive = true;
            break;
        }
    }

    try std.testing.expect(found_additive);
}

test "renderLine with zero width produces no glow" {
    const size = 64;
    const image = Image.init(size, size);
    const viewport = image.viewport();

    var buffer = [_]Linear{Linear.black} ** (size * size);

    const band = try image.band(Linear, &buffer, size, 0);
    const glow = Self{ .normalized_width = 0.0, .color = Linear.white };
    const line = Segment{ .start = .{ -1, 0 }, .end = .{ 0, 0 } };

    glow.renderLine(band, viewport, line, 0.0, Linear.white);

    for (&buffer) |pixel| {
        try std.testing.expectEqual(Linear.black.vec, pixel.vec);
    }
}

test "renderPrismEdges with zero width produces no glow" {
    const prism = Prism.init(0.8);
    const size = 64;
    const image = Image.init(size, size);
    const viewport = image.viewport();

    var buffer = [_]Linear{Linear.black} ** (size * size);

    const band = try image.band(Linear, &buffer, size, 0);
    const glow = Self{ .normalized_width = 0.0, .color = Linear.white };

    glow.renderPrismEdges(band, viewport, prism);

    for (&buffer) |pixel| {
        try std.testing.expectEqual(Linear.black.vec, pixel.vec);
    }
}
