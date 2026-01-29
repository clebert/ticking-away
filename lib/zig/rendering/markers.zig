const std = @import("std");

const circle = @import("../geometry/boundary.zig");
const clip = @import("clip.zig");
const color = @import("../color/color.zig");
const glow = @import("glow.zig");
const line = @import("../geometry/segment.zig");
const vec2 = @import("../math/vec2.zig");

const pi = std.math.pi;

/// Number of hour markers on the watch face.
pub const marker_count: usize = 12;

/// Markers end at 98% of radius.
pub const outer_percent: f32 = 0.98;

/// Marker configuration.
pub const Config = struct {
    visible: bool = true,
    length: f32 = 0.15,
    glow_width: f32 = 0.02,
    glow_intensity: f32 = 0.6,
    falloff: glow.Falloff = .quadratic,
};

/// Geometry context for markers.
pub const Geometry = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    boundary: circle.Circle = undefined,

    pub fn init(center_x: f32, center_y: f32, radius: f32) Geometry {
        return .{
            .center_x = center_x,
            .center_y = center_y,
            .radius = radius,
            .boundary = circle.Circle.init(vec2.xy(center_x, center_y), radius),
        };
    }

    pub fn circleClip(self: *const Geometry) clip.Region {
        return .{ .circle = &self.boundary };
    }
};

/// A marker ready for rendering via band.Context.renderGlowLine.
pub const Marker = struct {
    segment: line.Segment,
    glow_config: glow.Config,
};

/// Compute markers for all 12 hours, ready for rendering.
pub fn computeMarkers(geometry: Geometry, config: Config) [marker_count]Marker {
    @setFloatMode(.optimized);
    var markers: [marker_count]Marker = undefined;
    const glow_width = geometry.radius * config.glow_width;

    for (0..marker_count) |h| {
        // h=0 is 12 o'clock, h=3 is 3 o'clock, etc.
        // Standard clock: 0 degrees is 3 o'clock, so offset by -3 hours
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
                .color = .{ .uniform = color.rgb(
                    config.glow_intensity,
                    config.glow_intensity,
                    config.glow_intensity,
                ) },
            },
        };
    }

    return markers;
}

test "marker positions" {
    const geometry = Geometry{
        .center_x = 100,
        .center_y = 100,
        .radius = 50,
    };
    const config = Config{};
    const markers = computeMarkers(geometry, config);

    // Get outer endpoints (start + dir gives the outer point)
    const m0_end = markers[0].segment.start + markers[0].segment.dir;
    const m3_end = markers[3].segment.start + markers[3].segment.dir;
    const m6_end = markers[6].segment.start + markers[6].segment.dir;
    const m9_end = markers[9].segment.start + markers[9].segment.dir;

    // 12 o'clock should be at top (y < center_y)
    try std.testing.expect(m0_end[1] < geometry.center_y);

    // 3 o'clock should be at right (x > center_x)
    try std.testing.expect(m3_end[0] > geometry.center_x);

    // 6 o'clock should be at bottom (y > center_y)
    try std.testing.expect(m6_end[1] > geometry.center_y);

    // 9 o'clock should be at left (x < center_x)
    try std.testing.expect(m9_end[0] < geometry.center_x);
}
