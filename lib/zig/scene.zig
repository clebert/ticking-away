const std = @import("std");

const clock = @import("clock.zig");
const color = @import("color/color.zig");
const palette = @import("color/palette.zig");
const boundary = @import("geometry/boundary.zig");
const prism = @import("geometry/prism.zig");
const line = @import("geometry/segment.zig");
const trig = @import("math/trig.zig");
const vec2 = @import("math/vec2.zig");
const band = @import("rendering/band.zig");
const clip = @import("rendering/clip.zig");
const glow = @import("rendering/glow.zig");
const gradient = @import("rendering/gradient.zig");
const markers = @import("rendering/markers.zig");
const spectrum = @import("spectrum.zig");

pub const PrismConfig = struct {
    size: f32 = 0.65,
    rainbow_spread: f32 = 0.5,
};

pub const GlowConfig = struct {
    color: color.Color = color.rgb(0.5, 0.5, 0.5),
    width: f32 = 0.15,
    intensity: f32 = 0.6,
    falloff: glow.Falloff = .quadratic,
};

pub const RayConfig = struct {
    glow_width: f32 = 0.025,
    intensity: f32 = 0.8,
    falloff: glow.Falloff = .quadratic,
    palette_type: palette.Type = .oklch_balanced,
    gradient_fill: bool = true,
    reverse: bool = false,
};

pub const Scene = struct {
    width: usize,
    height: usize,
    center: vec2.Vec2,
    radius: f32,

    time_minutes: f32 = 0,

    prism: prism.Prism = undefined,
    prism_dirty: bool = true,

    prism_config: PrismConfig = .{},
    glow_config: GlowConfig = .{},
    ray_config: RayConfig = .{},
    marker_config: markers.Config = .{},

    palette_cache: palette.Cache = undefined,
    palette_initialized: bool = false,

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

    fn setTimeMinutes(self: *Scene, minutes: f32) void {
        self.time_minutes = @mod(minutes, 720.0);
    }

    pub fn setPrismConfig(self: *Scene, config: PrismConfig) void {
        self.prism_config = config;
        self.prism_dirty = true;
    }

    pub fn setGlowConfig(self: *Scene, config: GlowConfig) void {
        self.glow_config = config;
    }

    pub fn setRayConfig(self: *Scene, config: RayConfig) void {
        if (config.palette_type != self.ray_config.palette_type) {
            self.palette_initialized = false;
        }
        self.ray_config = config;
    }

    pub fn setMarkerConfig(self: *Scene, config: markers.Config) void {
        self.marker_config = config;
    }

    fn updatePrism(self: *Scene) void {
        const prism_size = self.prism_config.size * self.radius;
        self.prism = prism.Prism.init(self.center, prism_size);
        self.prism_dirty = false;
    }

    fn ensurePaletteCache(self: *Scene) *const palette.Cache {
        if (!self.palette_initialized) {
            self.palette_cache = palette.Cache.init(self.ray_config.palette_type);
            self.palette_initialized = true;
        }
        return &self.palette_cache;
    }

    pub fn renderBand(self: *Scene, ctx: *band.Context) void {
        if (self.prism_dirty) {
            self.updatePrism();
        }

        ctx.clearWithBackground(self.center[0], self.center[1], self.radius);

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
        );

        const circle_clip = clip.Region{ .boundary = &bnd };
        const prism_tri = &self.prism;
        const cache = self.ensurePaletteCache();

        // Determine internal ray rendering mode based on gradient fill
        const use_gradient_intensity = self.ray_config.gradient_fill;
        const draw_internal_colored_rays = !self.ray_config.gradient_fill or self.prism_config.rainbow_spread <= 0.99;
        const glow_width = self.ray_config.glow_width * self.radius;

        for (paths.bands, 0..) |band_path, i| {
            // Handle reverse spectrum: swap color indices if reversed
            const color_idx = if (self.ray_config.reverse) clock.band_count - 1 - i else i;
            const band_color = cache.getColor(color_idx);

            // Draw entry ray for each band (white light = all wavelengths combined)
            if (paths.entry_ray) |entry_seg| {
                const segment = line.Segment.init(entry_seg.start, entry_seg.end);
                glow.renderLine(ctx, segment, .{
                    .width = glow_width,
                    .falloff = self.ray_config.falloff,
                    .color = .{ .uniform = color.white },
                    .intensity = .{ .uniform = self.ray_config.intensity },
                }, circle_clip, prism_tri);
            }

            if (paths.needs_bounce) {
                // Entry → bounce segment: WHITE with uniform intensity
                if (band_path.internal1) |seg| {
                    const segment = line.Segment.init(seg.start, seg.end);
                    glow.renderLine(ctx, segment, .{
                        .width = glow_width,
                        .falloff = self.ray_config.falloff,
                        .color = .{ .uniform = color.white },
                        .intensity = .{ .uniform = self.ray_config.intensity },
                    }, .{ .prism = prism_tri }, null);
                }

                // Bounce → exit segment: COLORED with gradient intensity fade
                if (band_path.internal2) |seg| {
                    if (draw_internal_colored_rays) {
                        const segment = line.Segment.init(seg.start, seg.end);
                        if (use_gradient_intensity) {
                            glow.renderLine(ctx, segment, .{
                                .width = glow_width,
                                .falloff = self.ray_config.falloff,
                                .color = .{ .uniform = band_color },
                                .intensity = .{ .gradient = .{ .start = self.ray_config.intensity, .end = 0.0 } },
                            }, .{ .prism = prism_tri }, null);
                        } else {
                            glow.renderLine(ctx, segment, .{
                                .width = glow_width,
                                .falloff = self.ray_config.falloff,
                                .color = .{ .uniform = band_color },
                                .intensity = .{ .uniform = self.ray_config.intensity },
                            }, .{ .prism = prism_tri }, null);
                        }
                    }
                }
            } else {
                // Direct path: entry → exit, COLORED with gradient intensity fade
                if (band_path.internal1) |seg| {
                    if (draw_internal_colored_rays) {
                        const segment = line.Segment.init(seg.start, seg.end);
                        if (use_gradient_intensity) {
                            glow.renderLine(ctx, segment, .{
                                .width = glow_width,
                                .falloff = self.ray_config.falloff,
                                .color = .{ .uniform = band_color },
                                .intensity = .{ .gradient = .{ .start = self.ray_config.intensity, .end = 0.0 } },
                            }, .{ .prism = prism_tri }, null);
                        } else {
                            glow.renderLine(ctx, segment, .{
                                .width = glow_width,
                                .falloff = self.ray_config.falloff,
                                .color = .{ .uniform = band_color },
                                .intensity = .{ .uniform = self.ray_config.intensity },
                            }, .{ .prism = prism_tri }, null);
                        }
                    }
                }
            }

            // Only draw exit rays when gradient fill is disabled
            // (gradient fill replaces the exit rays with a smooth color fill)
            if (!self.ray_config.gradient_fill) {
                if (band_path.exit_ray) |seg| {
                    const segment = line.Segment.init(seg.start, seg.end);
                    glow.renderLine(ctx, segment, .{
                        .width = glow_width,
                        .falloff = self.ray_config.falloff,
                        .color = .{ .uniform = band_color },
                        .intensity = .{ .uniform = self.ray_config.intensity },
                    }, circle_clip, prism_tri);
                }
            }
        }

        if (self.ray_config.gradient_fill) gradient_fill: {
            const first_band = paths.bands[0];
            const last_band = paths.bands[clock.band_count - 1];

            const first_exit_ray = first_band.exit_ray orelse break :gradient_fill;
            const last_exit_ray = last_band.exit_ray orelse break :gradient_fill;

            // Compute angles from CENTER to where boundary rays hit CIRCLE
            const pi = std.math.pi;
            const tau = std.math.tau;
            const edge_margin_factor = 0.5 / @as(f32, @floatFromInt(clock.band_count - 1));

            const first_border = first_exit_ray.end;
            const last_border = last_exit_ray.end;

            const ext_angle_first = trig.atan2(
                first_border[1] - self.center[1],
                first_border[0] - self.center[0],
            );
            const ext_angle_last = trig.atan2(
                last_border[1] - self.center[1],
                last_border[0] - self.center[0],
            );

            var ray_span = ext_angle_last - ext_angle_first;
            if (ray_span > pi) ray_span -= tau;
            if (ray_span < -pi) ray_span += tau;
            const edge_margin = ray_span * edge_margin_factor;

            // External gradient (outside prism, inside circle)
            gradient.render(
                ctx,
                .{
                    .mode = .external,
                    .origin_x = self.center[0],
                    .origin_y = self.center[1],
                    .angle_start = ext_angle_first - edge_margin,
                    .angle_end = ext_angle_last + edge_margin,
                    .intensity = self.ray_config.intensity,
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

            const first_exit = first_band.prism_exit orelse break :gradient_fill;
            const last_exit = last_band.prism_exit orelse break :gradient_fill;

            const internal_angle_first = trig.atan2(
                first_exit[1] - grad_origin[1],
                first_exit[0] - grad_origin[0],
            );
            const internal_angle_last = trig.atan2(
                last_exit[1] - grad_origin[1],
                last_exit[0] - grad_origin[0],
            );

            var internal_span = internal_angle_last - internal_angle_first;
            if (internal_span > pi) internal_span -= tau;
            if (internal_span < -pi) internal_span += tau;
            const internal_edge_margin = internal_span * edge_margin_factor;

            gradient.render(
                ctx,
                .{
                    .mode = .internal,
                    .origin_x = grad_origin[0],
                    .origin_y = grad_origin[1],
                    .angle_start = internal_angle_first - internal_edge_margin,
                    .angle_end = internal_angle_last + internal_edge_margin,
                    .intensity = self.ray_config.intensity,
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
            ctx,
            self.prism,
            self.glow_config.color,
            self.glow_config.width * self.radius,
            self.glow_config.intensity,
            self.glow_config.falloff,
        );

        if (self.marker_config.visible) {
            const marker_geometry = markers.Geometry.init(
                self.center[0],
                self.center[1],
                self.radius,
            );
            const hour_markers = markers.computeMarkers(marker_geometry, self.marker_config);
            const marker_clip = marker_geometry.circleClip();

            for (hour_markers) |m| {
                glow.renderLine(ctx, m.segment, m.glow_config, marker_clip, null);
            }
        }
    }
};
