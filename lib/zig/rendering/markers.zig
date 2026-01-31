const std = @import("std");
const pi = std.math.pi;

const color_space = @import("../color/color_space.zig");
const boundary = @import("../geometry/boundary.zig");
const line = @import("../geometry/segment.zig");
const vec2 = @import("../math/vec2.zig");
const clip = @import("clip.zig");
const glow = @import("glow.zig");

pub const marker_count: usize = 12;

const outer_percent: f32 = 0.98;

pub const Config = struct {
    visible: bool = true,
    length: f32 = 0.15,
    glow_width: f32 = 0.02,
    glow_intensity: f32 = 0.6,
    falloff: glow.Falloff = .quadratic,
};

pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    bnd: boundary.Boundary,

    pub fn init(center_x: f32, center_y: f32, radius: f32) Geometry {
        return .{
            .center_x = center_x,
            .center_y = center_y,
            .radius = radius,
            .bnd = boundary.Boundary.init(vec2.xy(center_x, center_y), radius),
        };
    }

    pub fn circleClip(self: *const Geometry) clip.Region {
        return .{ .boundary = &self.bnd };
    }
};

pub const Marker = struct {
    segment: line.Segment,
    glow_config: glow.Config,
};

pub fn computeMarkers(geometry: Geometry, config: Config) [marker_count]Marker {
    var markers: [marker_count]Marker = undefined;
    const glow_width = geometry.radius * config.glow_width;

    for (0..marker_count) |h| {
        const angle = (@as(f32, @floatFromInt(h)) - 3.0) * 30.0 * pi / 180.0;

        const inner_r = geometry.radius * (1.0 - config.length);
        const outer_r = geometry.radius * outer_percent;

        const cos_a = @cos(angle);
        const sin_a = @sin(angle);

        const start = vec2.xy(
            geometry.center_x + cos_a * inner_r,
            geometry.center_y + sin_a * inner_r,
        );
        const end = vec2.xy(
            geometry.center_x + cos_a * outer_r,
            geometry.center_y + sin_a * outer_r,
        );

        markers[h] = .{
            .segment = line.Segment.init(start, end),
            .glow_config = .{
                .width = glow_width,
                .falloff = config.falloff,
                .color = .{ .uniform = color_space.Linear.init(
                    config.glow_intensity,
                    config.glow_intensity,
                    config.glow_intensity,
                    1.0,
                ) },
            },
        };
    }

    return markers;
}
