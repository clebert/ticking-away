const std = @import("std");

const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Ray = @import("Ray.zig");
const Segment = @import("Segment.zig");

const Self = @This();

external_minute_hand: Segment,
internal_minute_hand: ?Segment,
internal_hour_hand: std.EnumArray(Rainbow.Color, Segment),
external_hour_hand: std.EnumArray(Rainbow.Color, Segment),

pub fn init(time_minutes: f32, watchface_radius: f32, prism: Prism, rainbow_spread: f32) Self {
    std.debug.assert(time_minutes >= 0.0);
    std.debug.assert(rainbow_spread > 0.0 and rainbow_spread <= 1.0);
    std.debug.assert(watchface_radius > 0.0 and watchface_radius <= 1.0);

    const n_hours: usize = @intFromFloat(time_minutes / 60.0);
    const hour: f32 = @floatFromInt(@mod(n_hours, 12));
    const minute = time_minutes - @as(f32, @floatFromInt(n_hours)) * 60.0;

    const external_minute_hand = computeExternalMinuteHand(minute, watchface_radius, prism);

    _ = external_minute_hand; // autofix
    _ = hour; // autofix

}

const hour_arc: f32 = std.math.pi / 6.0; // 2π/12 = π/6 ≈ 30° (one hour moves 30°)
const minute_arc: f32 = std.math.pi / 30.0; // 2π/60 = π/30 ≈ 6° (one minute moves 6°)

const vertex_angles = std.EnumArray(Prism.VertexId, f32).init(.{
    .apex = -std.math.pi / 2.0, // −π/2 (−90°, 12 o'clock)
    .bottom_right = std.math.pi / 6.0, // π/6 (30°, 4 o'clock area)
    .bottom_left = 5.0 * std.math.pi / 6.0, // 5π/6 (150°, 8 o'clock area)
});

const vertex_tolerance = minute_arc / 2.0; // ±3° (half a minute)

fn computeExternalMinuteHand(minute: f32, watchface_radius: f32, prism: Prism) ?Segment {
    const minute_angle = vertex_angles.get(.apex) + (minute / 60.0) * std.math.tau;

    const minute_position: @Vector(2, f32) = .{ @cos(minute_angle), @sin(minute_angle) } *
        @as(@Vector(2, f32), @splat(watchface_radius));

    for (std.meta.tags(Prism.VertexId)) |vertex_id| {
        if (@abs(minute_angle - vertex_angles.get(vertex_id)) < vertex_tolerance) return .{
            .start = minute_position,
            .end = prism.vertices.get(vertex_id),
        };
    }

    // Ray from watchface edge at minute position, pointing toward center.
    const external_minute_ray = Ray.init(minute_position, .{ 0, 0 });

    const closest_edge_intersection = Ray.SegmentIntersection.closest(
        Ray.SegmentIntersection.closest(
            external_minute_ray.intersectSegment(prism.edges.get(.right)),
            external_minute_ray.intersectSegment(prism.edges.get(.bottom)),
        ),
        external_minute_ray.intersectSegment(prism.edges.get(.left)),
    ) orelse return null;

    return .{
        .start = minute_position,
        .end = closest_edge_intersection.hit,
    };
}

// clock. colorExitAngle
// hour_angle
// rainbow_spread
// Ray.fromAngle
// prism.centroid() => 0/0 => entfällt
