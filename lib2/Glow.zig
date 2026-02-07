const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
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
    if (self.clip_radius != null) {
        self.renderLineInner(true, band, viewport, line);
    } else {
        self.renderLineInner(false, band, viewport, line);
    }
}

inline fn renderLineInner(
    self: Self,
    comptime clipped: bool,
    band: *Image.Band(Linear),
    viewport: Image.Viewport,
    line: Segment,
) void {
    const width_squared = self.style.width * self.style.width;
    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    const width_vec: @Vector(2, f32) = @splat(self.style.width);
    const min_pixel = viewport.toPixel(@min(line.start, line.end) - width_vec);
    const max_pixel = viewport.toPixel(@max(line.start, line.end) + width_vec);

    const x_start = util.floorClamped(min_pixel[0], band.width);
    const x_end = util.ceilClamped(max_pixel[0], band.width);
    const y_start = util.floorClamped(min_pixel[1] - y_offset, band_height);
    const y_end = util.ceilClamped(max_pixel[1] - y_offset, band_height);

    const uniform_intensity: ?f32 = switch (self.intensity) {
        .uniform => |v| v,
        .gradient => null,
    };

    for (y_start..y_end) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_start..x_end) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            if (comptime clipped) {
                const radius = self.clip_radius.?;

                if (@reduce(.Add, point * point) > radius * radius) continue;
            }

            const projection = line.project(point);

            if (projection.distance_squared >= width_squared) continue;

            const radial =
                self.style.falloff.apply(@sqrt(projection.distance_squared) / self.style.width);

            const intensity = radial * (uniform_intensity orelse self.intensity.at(projection.normalized_position));

            const pixel = band.colorAt(x, local_y);
            const contribution = self.color.vec * @as(@Vector(4, f32), @splat(intensity));

            pixel.vec = @max(pixel.vec, contribution);
        }
    }
}
