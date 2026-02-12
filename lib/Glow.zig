const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Segment = @import("Segment.zig");
const util = @import("util.zig");

const Self = @This();

pub const Falloff = enum {
    linear,
    quadratic,
    cubic,
    exponential,

    fn apply(self: Falloff, normalized_distance: f32) f32 {
        const proximity = 1 - normalized_distance;

        return switch (self) {
            .linear => proximity,
            .quadratic => proximity * proximity,
            .cubic => proximity * proximity * proximity,
            .exponential => @exp(-3 * normalized_distance) * proximity,
        };
    }
};

pub const ClipRegion = union(enum) {
    none,
    circle,
    prism: Prism,
};

pub const LineOptions = struct {
    clip: ClipRegion = .none,
    fading: bool = false,
    rainbow: ?Rainbow = null,
};

normalized_width: f32,
falloff: Falloff,
color: Linear,

pub fn renderLine(
    self: Self,
    band: *Image.Band(Linear),
    viewport: anytype,
    line: Segment,
    options: LineOptions,
) void {
    std.debug.assert(self.normalized_width > 0.0 and self.normalized_width <= 1.0);

    switch (options.clip) {
        .none => if (options.fading) {
            self.renderLineInner(true, .none, band, viewport, line, undefined, options.rainbow);
        } else {
            self.renderLineInner(false, .none, band, viewport, line, undefined, options.rainbow);
        },
        .circle => if (options.fading) {
            self.renderLineInner(true, .circle, band, viewport, line, undefined, options.rainbow);
        } else {
            self.renderLineInner(false, .circle, band, viewport, line, undefined, options.rainbow);
        },
        .prism => |prism| if (options.fading) {
            self.renderLineInner(true, .prism, band, viewport, line, prism, options.rainbow);
        } else {
            self.renderLineInner(false, .prism, band, viewport, line, prism, options.rainbow);
        },
    }
}

inline fn renderLineInner(
    self: Self,
    comptime fading: bool,
    comptime clip_region: std.meta.Tag(ClipRegion),
    band: *Image.Band(Linear),
    viewport: anytype,
    line: Segment,
    clip_prism: Prism,
    rainbow: ?Rainbow,
) void {
    const width_squared = self.normalized_width * self.normalized_width;
    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const width_vec: @Vector(2, f32) = @splat(self.normalized_width);
    const pixel_a = viewport.toPixel(@min(line.start, line.end) - width_vec);
    const pixel_b = viewport.toPixel(@max(line.start, line.end) + width_vec);
    const min_pixel = @min(pixel_a, pixel_b);
    const max_pixel = @max(pixel_a, pixel_b);

    const x_start = util.floorClamped(min_pixel[0], band.width);
    const x_end = util.ceilClamped(max_pixel[0], band.width);
    const y_start = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_end = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    const line_direction = line.end - line.start;
    const line_length = @sqrt(@reduce(.Add, line_direction * line_direction));
    const inv_line_length = if (line_length > std.math.floatEps(f32)) 1.0 / line_length else 0;

    for (y_start..y_end) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_start..x_end) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            if (comptime clip_region == .circle) {
                if (@reduce(.Add, point * point) > 1.0) continue;
            }

            const projection = line.project(point);

            if (projection.distance_squared >= width_squared) continue;

            if (comptime clip_region == .prism) {
                if (!clip_prism.containsPoint(point)) continue;
            }

            const radial =
                self.falloff.apply(@sqrt(projection.distance_squared) / self.normalized_width);

            const fade = 1.0 - projection.normalized_position;
            const intensity = radial * if (comptime fading) fade * fade else 1.0;

            const line_color = if (rainbow) |r| blk: {
                const start_to_point = point - line.start;

                const signed_distance =
                    (line_direction[0] * start_to_point[1] - line_direction[1] * start_to_point[0]) *
                    inv_line_length;

                const rainbow_color = r.interpolate(
                    std.math.clamp(signed_distance / self.normalized_width * 0.5 + 0.5, 0.0, 1.0),
                );

                const dispersion = @sqrt(
                    std.math.clamp(projection.normalized_position * 4.0, 0.0, 1.0),
                );

                break :blk Linear.lerp(Linear.white, rainbow_color, dispersion);
            } else self.color;

            const pixel = band.colorAt(x, local_y);
            const contribution = line_color.vec * @as(@Vector(4, f32), @splat(intensity));

            pixel.vec = @max(pixel.vec, contribution);
        }
    }
}

pub fn renderPrismEdges(
    self: Self,
    band: *Image.Band(Linear),
    viewport: anytype,
    prism: Prism,
) void {
    std.debug.assert(self.normalized_width > 0.0 and self.normalized_width <= 1.0);

    const width = self.normalized_width;
    const smooth_k = width * 0.5;

    // smoothMin subtracts at most h²·k·0.25 from the true min, so glow can
    // appear slightly beyond `width`. Pad the early-out to avoid clipping it.
    const early_out_threshold = width + smooth_k * 0.25;
    const early_out_threshold_squared = early_out_threshold * early_out_threshold;
    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const prism_bounds = prism.bounds();
    const pixel_a = viewport.toPixel(.{ prism_bounds[0], prism_bounds[1] });
    const pixel_b = viewport.toPixel(.{ prism_bounds[2], prism_bounds[3] });
    const min_pixel = @min(pixel_a, pixel_b);
    const max_pixel = @max(pixel_a, pixel_b);

    const x_start = util.floorClamped(min_pixel[0], band.width);
    const x_end = util.ceilClamped(max_pixel[0], band.width);
    const y_start = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_end = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    for (y_start..y_end) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_start..x_end) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            if (!prism.containsPoint(point)) continue;

            const proj0 = prism.edges.get(.right).project(point);
            const proj1 = prism.edges.get(.bottom).project(point);
            const proj2 = prism.edges.get(.left).project(point);

            const min_distance_squared = @min(
                proj0.distance_squared,
                @min(proj1.distance_squared, proj2.distance_squared),
            );

            if (min_distance_squared >= early_out_threshold_squared) continue;

            const d0 = @sqrt(proj0.distance_squared);
            const d1 = @sqrt(proj1.distance_squared);
            const d2 = @sqrt(proj2.distance_squared);
            const distance = smoothMin(smoothMin(d0, d1, smooth_k), d2, smooth_k);

            if (distance >= width) continue;

            const normalized_distance = @max(distance / width, 0.0);
            const intensity = self.falloff.apply(normalized_distance);
            const blended_color = Linear.lerp(Linear.white, self.color, @sqrt(normalized_distance));

            const pixel = band.colorAt(x, local_y);
            const contribution = blended_color.vec * @as(@Vector(4, f32), @splat(intensity));

            pixel.vec = pixel.vec + contribution;
        }
    }
}

fn smoothMin(a: f32, b: f32, k: f32) f32 {
    const h = @max(k - @abs(a - b), 0) / k;

    return @min(a, b) - h * h * k * 0.25;
}

test "smoothMin returns minimum when values are far apart" {
    const result = smoothMin(1.0, 5.0, 0.5);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result, 0.01);
}

test "smoothMin blends when values are equal" {
    const result = smoothMin(1.0, 1.0, 1.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.75), result, 1e-6);
}

test "renderPrismEdges produces glow inside prism" {
    const prism = Prism.init(0.8);
    const image_size = 64;
    const image = Image.init(image_size, image_size);
    const viewport = image.viewport();

    var buffer = [_]Linear{Linear.black} ** (image_size * image_size);
    var band = image.band(Linear, &buffer, image_size, 0) catch unreachable;

    const glow = Self{ .normalized_width = 0.15, .falloff = .linear, .color = Linear.white };

    glow.renderPrismEdges(&band, viewport, prism);

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
    var band = image.band(Linear, &buffer, 64, 0) catch unreachable;

    const glow = Self{ .normalized_width = 0.15, .falloff = .linear, .color = Linear.white };

    glow.renderPrismEdges(&band, viewport, prism);

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
    var band = image.band(Linear, &buffer, image_size, 0) catch unreachable;

    const glow = Self{ .normalized_width = 0.15, .falloff = .linear, .color = Linear.white };

    glow.renderPrismEdges(&band, viewport, prism);

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
    var band = image.band(Linear, &buffer, image_size, 0) catch unreachable;

    const glow = Self{ .normalized_width = 0.15, .falloff = .linear, .color = Linear.white };

    glow.renderPrismEdges(&band, viewport, prism);

    var found_additive = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > base.vec[0] + 0.01) {
            found_additive = true;
            break;
        }
    }

    try std.testing.expect(found_additive);
}
