const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Segment = @import("Segment.zig");

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

pub const Style = struct {
    width: f32,
    falloff: Falloff,
};

pub const Intensity = union(enum) {
    uniform: f32,
    gradient: struct { start: f32, end: f32 },

    fn at(self: Intensity, normalized_position: f32) f32 {
        return switch (self) {
            .uniform => |v| v,
            .gradient => |g| g.start + (g.end - g.start) * normalized_position,
        };
    }
};

style: Style,
color: Linear,
intensity: Intensity = .{ .uniform = 1.0 },
clip_radius: ?f32 = null,

pub fn renderLine(
    self: Self,
    band: *Image.Band(Linear),
    viewport: Image.Viewport,
    line: Segment,
) void {
    const width_squared = self.style.width * self.style.width;
    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    // Convert normalized geometry bounds to pixel space for iteration
    const width_vec: @Vector(2, f32) = @splat(self.style.width);
    const min_pixel = viewport.toPixel(@min(line.start, line.end) - width_vec);
    const max_pixel = viewport.toPixel(@max(line.start, line.end) + width_vec);

    const x_start = floorClamped(min_pixel[0], band.width);
    const x_end = ceilClamped(max_pixel[0], band.width);
    const y_start = floorClamped(min_pixel[1] - y_offset, band_height);
    const y_end = ceilClamped(max_pixel[1] - y_offset, band_height);

    for (y_start..y_end) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_start..x_end) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            if (self.clip_radius) |radius| {
                if (@reduce(.Add, point * point) > radius * radius) continue;
            }

            const projection = line.project(point);

            if (projection.distance_squared >= width_squared) continue;

            const radial =
                self.style.falloff.apply(@sqrt(projection.distance_squared) / self.style.width);

            const intensity = radial * self.intensity.at(projection.normalized_position);

            const color = band.colorAt(x, local_y);
            const contribution = self.color.vec * @as(@Vector(4, f32), @splat(intensity));

            color.vec = @max(color.vec, contribution);
        }
    }
}

fn floorClamped(value: f32, max: usize) usize {
    if (value <= 0) return 0;

    const upper: f32 = @floatFromInt(max);

    if (value >= upper) return max;

    return @intFromFloat(@floor(value));
}

fn ceilClamped(value: f32, max: usize) usize {
    if (value <= 0) return 0;

    const upper: f32 = @floatFromInt(max);

    if (value >= upper) return max;

    return @intFromFloat(@ceil(value));
}
