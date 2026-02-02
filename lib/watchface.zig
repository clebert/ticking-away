const std = @import("std");

const boundary = @import("boundary.zig");
const clip = @import("clip.zig");
const clock = @import("clock.zig");
const color_space = @import("color_space.zig");
const frame = @import("frame.zig");
const glow = @import("glow.zig");
const gradient = @import("gradient.zig");
const line = @import("line.zig");
const markers = @import("markers.zig");
const Prism = @import("Prism.zig");
const rainbow = @import("rainbow.zig");
const spectrum = @import("spectrum.zig");
const vec2 = @import("vec2.zig");

pub const PrismConfig = struct {
    size: f32 = 0.65,
    rainbow_spread: f32 = 0.5,
    force_opposite_bounce: bool = false,
};

pub const GlowConfig = struct {
    color: color_space.Linear = color_space.Linear.init(0.5, 0.5, 0.5, 1.0),
    width: f32 = 0.15,
    falloff: glow.Falloff = .quadratic,
};

pub const RayConfig = struct {
    glow_width: f32 = 0.025,
    falloff: glow.Falloff = .quadratic,
    palette_type: rainbow.PaletteType = .oklch_balanced,
    gradient_fill: bool = true,
    reverse: bool = false,
};

pub const Scene = struct {
    width: usize,
    height: usize,

    center: vec2.Vec2,
    radius: f32,

    time_minutes: f32 = 0,

    prism: Prism = undefined,
    prism_dirty: bool = true,

    prism_config: PrismConfig = .{},
    glow_config: GlowConfig = .{},
    ray_config: RayConfig = .{},
    marker_config: markers.Config = .{},

    pub fn init(width: usize, height: usize) Scene {
        const min_dim: f32 = @floatFromInt(@min(width, height));
        const radius = min_dim / 2.0;
        const center = vec2.xy(
            @as(f32, @floatFromInt(width)) / 2.0,
            @as(f32, @floatFromInt(height)) / 2.0,
        );

        return .{
            .width = width,
            .height = height,
            .center = center,
            .radius = radius,
        };
    }

    pub fn setTime(self: *Scene, hour: i32, minute: f32) void {
        const h = @mod(hour, 12);
        const m = @mod(minute, 60.0);
        self.time_minutes = @as(f32, @floatFromInt(h)) * 60.0 + m;
    }

    pub fn setPrismConfig(self: *Scene, config: PrismConfig) void {
        self.prism_config = config;
        self.prism_dirty = true;
    }

    pub fn setGlowConfig(self: *Scene, config: GlowConfig) void {
        self.glow_config = config;
    }

    pub fn setRayConfig(self: *Scene, config: RayConfig) void {
        self.ray_config = config;
    }

    pub fn setMarkerConfig(self: *Scene, config: markers.Config) void {
        self.marker_config = config;
    }

    fn updatePrism(self: *Scene) void {
        const prism_size = self.prism_config.size * self.radius;
        self.prism = Prism.init(self.center, prism_size);
        self.prism_dirty = false;
    }

    fn getPaletteCache(self: *const Scene) *const rainbow.PaletteCache {
        return rainbow.getPaletteCache(self.ray_config.palette_type);
    }

    const Geometry = struct {
        boundary: boundary.Boundary,
        paths: spectrum.Paths,
        marker_geometry: markers.Geometry,
        hour_markers: [markers.marker_count]markers.Marker,
        markers_visible: bool,
    };

    fn prepareGeometry(self: *Scene) Geometry {
        if (self.prism_dirty) {
            self.updatePrism();
        }

        const bnd = boundary.Boundary.init(self.center, self.radius);

        const hours_f = self.time_minutes / 60.0;
        const hours: i32 = @intFromFloat(hours_f);
        const hour: f32 = @floatFromInt(@mod(hours, 12));
        const minute = self.time_minutes - @as(f32, @floatFromInt(hours)) * 60.0;
        const hour_angle = clock.hourAngle(hour, minute);
        const entry = clock.entryPoint(self.center, self.radius, minute);

        const paths = spectrum.Paths.compute(
            entry,
            hour_angle,
            self.prism_config.rainbow_spread,
            self.prism,
            bnd,
            self.prism_config.force_opposite_bounce,
        );

        const marker_geometry = markers.Geometry.init(
            self.center[0],
            self.center[1],
            self.radius,
        );
        const hour_markers = markers.computeMarkers(marker_geometry, self.marker_config);

        return .{
            .boundary = bnd,
            .paths = paths,
            .marker_geometry = marker_geometry,
            .hour_markers = hour_markers,
            .markers_visible = self.marker_config.visible,
        };
    }

    fn renderBackground(self: *const Scene, band_linear: *frame.BandLinear) void {
        const r2 = self.radius * self.radius;
        const band_geometry = band_linear.geometry;

        for (0..band_geometry.height) |local_y| {
            const global_y = band_geometry.globalY(local_y);
            const y: f32 = @floatFromInt(global_y);
            const dy = y - self.center[1];
            const dy2 = dy * dy;

            for (0..band_geometry.width) |x| {
                const x_f: f32 = @floatFromInt(x);
                const dx = x_f - self.center[0];
                const dist2 = dx * dx + dy2;

                band_linear.colorAt(x, local_y).* = if (dist2 <= r2) color_space.Linear.black else color_space.Linear.white;
            }
        }
    }

    pub fn render(self: *Scene, band_linear: *frame.BandLinear) void {
        const geometry = self.prepareGeometry();

        self.renderBackground(band_linear);

        const circle_clip = clip.Region{ .boundary = &geometry.boundary };
        const prism_tri = &self.prism;
        const cache = self.getPaletteCache();
        const paths = &geometry.paths;

        const draw_internal_colored_rays = !self.ray_config.gradient_fill or self.prism_config.rainbow_spread <= 0.99;
        const glow_width = self.ray_config.glow_width * self.radius;
        const base_config = glow.Config{
            .width = glow_width,
            .falloff = self.ray_config.falloff,
            .color = .{ .uniform = color_space.Linear.white },
            .intensity = .{ .uniform = 1.0 },
        };

        for (std.enums.values(rainbow.Color)) |color| {
            const color_path = paths.colors.get(color);
            const color_idx = if (self.ray_config.reverse) color.reverse() else color;
            const linear_color = cache.getLinearColor(color_idx);

            // Entry ray (white light)
            if (paths.entry_ray) |entry_seg| {
                glow.renderLine(band_linear, line.Segment.init(entry_seg.start, entry_seg.end), base_config, circle_clip, prism_tri);
            }

            // Internal rays (inside prism)
            const colored_seg = if (paths.needs_bounce) color_path.internal2 else color_path.internal1;
            if (paths.needs_bounce) {
                if (color_path.internal1) |seg| {
                    glow.renderLine(band_linear, line.Segment.init(seg.start, seg.end), base_config, .{ .prism = prism_tri }, null);
                }
            }
            if (draw_internal_colored_rays) {
                if (colored_seg) |seg| {
                    var cfg = base_config;
                    cfg.color = .{ .uniform = linear_color };
                    if (self.ray_config.gradient_fill) {
                        cfg.intensity = .{ .gradient = .{ .start = 1.0, .end = 0.0 } };
                    }
                    glow.renderLine(band_linear, line.Segment.init(seg.start, seg.end), cfg, .{ .prism = prism_tri }, null);
                }
            }

            // Exit ray (only when gradient fill disabled)
            if (!self.ray_config.gradient_fill) {
                if (color_path.exit_ray) |seg| {
                    var cfg = base_config;
                    cfg.color = .{ .uniform = linear_color };
                    glow.renderLine(band_linear, line.Segment.init(seg.start, seg.end), cfg, circle_clip, prism_tri);
                }
            }
        }

        if (self.ray_config.gradient_fill) gradient_fill: {
            const first_color = paths.colors.get(.red);
            const last_color = paths.colors.get(.violet);

            const first_exit_ray = first_color.exit_ray orelse break :gradient_fill;
            const last_exit_ray = last_color.exit_ray orelse break :gradient_fill;

            // Compute angles from CENTER to where boundary rays hit CIRCLE
            const pi = std.math.pi;
            const tau = std.math.tau;
            const edge_margin_factor = 0.5 / @as(f32, @floatFromInt(clock.color_count - 1));

            const first_border = first_exit_ray.end;
            const last_border = last_exit_ray.end;

            const ext_angle_first = std.math.atan2(
                first_border[1] - self.center[1],
                first_border[0] - self.center[0],
            );
            const ext_angle_last = std.math.atan2(
                last_border[1] - self.center[1],
                last_border[0] - self.center[0],
            );

            var ray_span = ext_angle_last - ext_angle_first;
            if (ray_span > pi) ray_span -= tau;
            if (ray_span < -pi) ray_span += tau;
            const edge_margin = ray_span * edge_margin_factor;

            // External gradient (outside prism, inside circle)
            gradient.render(
                band_linear,
                .{
                    .mode = .external,
                    .origin_x = self.center[0],
                    .origin_y = self.center[1],
                    .angle_start = ext_angle_first - edge_margin,
                    .angle_end = ext_angle_last + edge_margin,
                    .reverse_spectrum = self.ray_config.reverse,
                },
                .{
                    .center_x = self.center[0],
                    .center_y = self.center[1],
                    .radius = self.radius,
                    .prism = self.prism,
                },
                cache,
            );

            // Internal gradient (inside prism)
            const grad_origin = if (paths.needs_bounce) paths.bounce_point else paths.entry_point;

            const first_exit = first_color.prism_exit orelse break :gradient_fill;
            const last_exit = last_color.prism_exit orelse break :gradient_fill;

            const internal_angle_first = std.math.atan2(
                first_exit[1] - grad_origin[1],
                first_exit[0] - grad_origin[0],
            );
            const internal_angle_last = std.math.atan2(
                last_exit[1] - grad_origin[1],
                last_exit[0] - grad_origin[0],
            );

            var internal_span = internal_angle_last - internal_angle_first;
            if (internal_span > pi) internal_span -= tau;
            if (internal_span < -pi) internal_span += tau;
            const internal_edge_margin = internal_span * edge_margin_factor;

            gradient.render(
                band_linear,
                .{
                    .mode = .internal,
                    .origin_x = grad_origin[0],
                    .origin_y = grad_origin[1],
                    .angle_start = internal_angle_first - internal_edge_margin,
                    .angle_end = internal_angle_last + internal_edge_margin,
                    .reverse_spectrum = self.ray_config.reverse,
                },
                .{
                    .center_x = self.center[0],
                    .center_y = self.center[1],
                    .radius = self.radius,
                    .prism = self.prism,
                },
                cache,
            );
        }

        glow.renderPrismEdges(
            band_linear,
            self.prism,
            self.glow_config.color,
            self.glow_config.width * self.radius,
            self.glow_config.falloff,
        );

        if (geometry.markers_visible) {
            const marker_clip = geometry.marker_geometry.circleClip();

            for (geometry.hour_markers) |m| {
                glow.renderLine(band_linear, m.segment, m.glow_config, marker_clip, null);
            }
        }
    }
};
