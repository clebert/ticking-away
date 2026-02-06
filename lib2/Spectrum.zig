const std = @import("std");
const tau = std.math.tau;
const pi = std.math.pi;

const Clock = @import("Clock.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Scene = @import("Scene.zig");

pub fn render(
    band: *Image.Band(Linear),
    viewport: Image.Viewport,
    scene: Scene,
    clock: Clock,
    rainbow: Rainbow,
) void {
    const edge_margin_factor = 0.5 / (@as(f32, @floatFromInt(Rainbow.color_count)) - 1.0);

    // External: fill between prism surface and circle boundary
    const external_origin: @Vector(2, f32) = .{ 0, 0 };
    const ext_angle_first = angleOf(external_origin, clock.external_hour_hand.get(.red).end);
    const ext_angle_last = angleOf(external_origin, clock.external_hour_hand.get(.violet).end);
    const ext_margin = edgeMargin(ext_angle_first, ext_angle_last, edge_margin_factor);

    renderRegion(
        band,
        viewport,
        external_origin,
        ext_angle_first - ext_margin,
        ext_angle_last + ext_margin,
        .{ .external = .{
            .radius_squared = scene.radius * scene.radius,
            .prism = scene.prism,
        } },
        rainbow,
    );

    // Internal: fill inside the prism
    const internal_origin = clock.internal_hour_hand.get(.red).start;
    const int_angle_first = angleOf(internal_origin, clock.internal_hour_hand.get(.red).end);
    const int_angle_last = angleOf(internal_origin, clock.internal_hour_hand.get(.violet).end);
    const int_margin = edgeMargin(int_angle_first, int_angle_last, edge_margin_factor);

    renderRegion(
        band,
        viewport,
        internal_origin,
        int_angle_first - int_margin,
        int_angle_last + int_margin,
        .{ .internal = scene.prism },
        rainbow,
    );
}

pub const Region = union(enum) {
    internal: Prism,
    external: struct {
        radius_squared: f32,
        prism: Prism,
    },
};

pub fn renderRegion(
    band: *Image.Band(Linear),
    viewport: Image.Viewport,
    origin: @Vector(2, f32),
    angle_start: f32,
    angle_end: f32,
    region: Region,
    rainbow: Rainbow,
) void {
    const a1_normalized = normalizeAngle(angle_start);
    const a2_normalized = normalizeAngle(angle_end);

    var angle_diff = a2_normalized - a1_normalized;
    if (angle_diff > pi) angle_diff -= tau;
    if (angle_diff < -pi) angle_diff += tau;

    const angle_span = @abs(angle_diff);
    if (angle_span < 0.001 or angle_span > pi) return;

    const reverse = angle_diff < 0;
    const a1_sorted = if (reverse) a2_normalized else a1_normalized;
    const a2_sorted = if (reverse) a1_normalized else a2_normalized;
    const wrap_around = a1_sorted > a2_sorted;

    const eps: f32 = 0.002;
    const a1 = if (wrap_around) normalizeAngle(a1_sorted - eps) else @max(a1_sorted - eps, 0);
    const a2 = if (wrap_around) normalizeAngle(a2_sorted + eps) else @min(a2_sorted + eps, tau - 0.0001);

    // Sector edge directions with eps margin for containment test
    const direction_start: @Vector(2, f32) = .{ @cos(a1), @sin(a1) };
    const direction_end: @Vector(2, f32) = .{ @cos(a2), @sin(a2) };

    // Exact edge directions for spectrum position interpolation
    const direction_start_exact: @Vector(2, f32) = .{ @cos(a1_sorted), @sin(a1_sorted) };
    const direction_end_exact: @Vector(2, f32) = .{ @cos(a2_sorted), @sin(a2_sorted) };

    const band_height = band.bandHeight();
    const y_offset: f32 = @floatFromInt(band.y_offset);

    // Compute bounds in normalized space, then convert to pixel space
    const normalized_bounds = switch (region) {
        .internal => |prism| prismBounds(prism),
        .external => |ext| sectorBounds(@sqrt(ext.radius_squared), a1, a2, wrap_around),
    };

    const min_pixel = viewport.toPixel(.{ normalized_bounds[0], normalized_bounds[1] });
    const max_pixel = viewport.toPixel(.{ normalized_bounds[2], normalized_bounds[3] });

    const x_min = floorClamped(min_pixel[0], band.width);
    const x_max = ceilClamped(max_pixel[0], band.width);
    const y_min = floorClamped(min_pixel[1] - y_offset, band_height);
    const y_max = ceilClamped(max_pixel[1] - y_offset, band_height);

    for (y_min..y_max) |local_y| {
        const pixel_y: f32 = @as(f32, @floatFromInt(band.imageY(local_y))) + 0.5;

        for (x_min..x_max) |x| {
            const pixel_x: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const point = viewport.toNormalized(.{ pixel_x, pixel_y });

            // Cross-product sector containment (cheapest test first)
            const dx = point[0] - origin[0];
            const dy = point[1] - origin[1];
            const cross_start = direction_start[0] * dy - direction_start[1] * dx;
            const cross_end = direction_end[0] * dy - direction_end[1] * dx;

            if (cross_start < 0 or cross_end > 0) continue;

            switch (region) {
                .internal => |prism| {
                    if (!prism.containsPoint(point)) continue;
                },
                .external => |ext| {
                    if (@reduce(.Add, point * point) > ext.radius_squared) continue;
                    if (ext.prism.containsPoint(point)) continue;
                },
            }

            // Cross-product ratio for spectrum position (replaces atan2)
            const cross_start_exact = direction_start_exact[0] * dy - direction_start_exact[1] * dx;
            const cross_end_exact = direction_end_exact[0] * dy - direction_end_exact[1] * dx;
            const spectrum_position_raw = std.math.clamp(cross_start_exact / (cross_start_exact - cross_end_exact), 0, 1);

            const spectrum_position = if (reverse) 1.0 - spectrum_position_raw else spectrum_position_raw;
            const color = rainbow.interpolate(spectrum_position);
            const pixel = band.colorAt(x, local_y);
            pixel.vec = pixel.vec + color.vec;
        }
    }
}

fn angleOf(from: @Vector(2, f32), to: @Vector(2, f32)) f32 {
    const delta = to - from;
    return std.math.atan2(delta[1], delta[0]);
}

fn edgeMargin(angle_first: f32, angle_last: f32, factor: f32) f32 {
    var span = angle_last - angle_first;
    if (span > pi) span -= tau;
    if (span < -pi) span += tau;
    return span * factor;
}

fn normalizeAngle(a: f32) f32 {
    return @mod(a, tau);
}

fn prismBounds(prism: Prism) @Vector(4, f32) {
    var min_val: @Vector(2, f32) = @splat(std.math.inf(f32));
    var max_val: @Vector(2, f32) = @splat(-std.math.inf(f32));

    inline for (std.meta.tags(Prism.VertexId)) |vid| {
        const v = prism.vertices.get(vid);
        min_val = @min(min_val, v);
        max_val = @max(max_val, v);
    }

    return .{ min_val[0], min_val[1], max_val[0], max_val[1] };
}

fn sectorBounds(radius: f32, a1: f32, a2: f32, wrap_around: bool) @Vector(4, f32) {
    const r: @Vector(2, f32) = @splat(radius);
    const p1 = @Vector(2, f32){ @cos(a1), @sin(a1) } * r;
    const p2 = @Vector(2, f32){ @cos(a2), @sin(a2) } * r;

    const origin: @Vector(2, f32) = .{ 0, 0 };
    var min_val = @min(origin, @min(p1, p2));
    var max_val = @max(origin, @max(p1, p2));

    const cardinal_angles = [_]f32{ 0, pi / 2.0, pi, 3.0 * pi / 2.0 };
    const cardinal_offsets = [_]@Vector(2, f32){
        .{ radius, 0 },
        .{ 0, radius },
        .{ -radius, 0 },
        .{ 0, -radius },
    };

    inline for (cardinal_angles, cardinal_offsets) |angle, offset| {
        if (angleInSector(angle, a1, a2, wrap_around)) {
            min_val = @min(min_val, offset);
            max_val = @max(max_val, offset);
        }
    }

    return .{ min_val[0], min_val[1], max_val[0], max_val[1] };
}

fn angleInSector(angle: f32, a1: f32, a2: f32, wrap_around: bool) bool {
    return if (wrap_around) angle >= a1 or angle <= a2 else angle >= a1 and angle <= a2;
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
