const std = @import("std");

const watchface = @import("watchface");
const compat = watchface.compat;

// =============================================================================
// WASM Memory Management
// =============================================================================

extern var __heap_base: u8;

export fn getHeapBase() [*]u8 {
    return @ptrCast(&__heap_base);
}

// =============================================================================
// Static State (cached between frames)
// =============================================================================

const max_dither_width = 5120;
const dither_buffer_size = max_dither_width * watchface.dither.error_diffusion.ErrorBuffer.rows * watchface.dither.error_diffusion.ErrorBuffer.channels;

var static_scene: watchface.scene.Scene = undefined;
var scene_initialized: bool = false;
var last_width: usize = 0;
var last_height: usize = 0;

var dither_error_backing: [dither_buffer_size]f32 = undefined;

// =============================================================================
// Render API
// =============================================================================

/// Render a test pattern using the Zig glow line renderer.
/// This is a minimal example to verify the WASM module works.
export fn renderTestPattern(buffer: [*]watchface.color.Color, width: u32, height: u32) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    var ctx = watchface.band.Context{
        .buffer = buffer[0 .. w * h],
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };

    // Clear to black
    ctx.clear();

    // Draw a diagonal glow line
    const segment = watchface.segment.Segment.init(
        watchface.vec2.xy(0, 0),
        watchface.vec2.xy(@floatFromInt(width), @floatFromInt(height)),
    );

    const config = watchface.glow.Config{
        .width = 5,
        .falloff = .exponential,
        .color = .{ .gradient = .{
            .start = watchface.color.rgb(1, 0, 0),
            .end = watchface.color.rgb(0, 0, 1),
        } },
    };

    watchface.glow.renderLine(&ctx,segment, config, null, null);
}

/// Clear the buffer to black.
export fn clearBuffer(buffer: [*]watchface.color.Color, width: u32, height: u32) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    var ctx = watchface.band.Context{
        .buffer = buffer[0 .. w * h],
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };

    ctx.clear();
}

/// Render a centered prism with glow effect.
export fn renderPrism(
    buffer: [*]watchface.color.Color,
    width: u32,
    height: u32,
    glow_width: f32,
    intensity: f32,
    falloff: u8,
) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);
    const w_f: f32 = @floatFromInt(width);
    const h_f: f32 = @floatFromInt(height);

    var ctx = watchface.band.Context{
        .buffer = buffer[0 .. w * h],
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };

    // Create centered equilateral triangle at 50% viewport size
    const center = watchface.vec2.xy(w_f / 2, h_f / 2);
    const base_width = @min(w_f, h_f) * 0.5;
    const tri = watchface.prism.Prism.init(center, base_width);

    watchface.glow.renderPrismEdges(&ctx,
        tri,
        watchface.color.rgba(1, 1, 1, 1),
        glow_width,
        intensity,
        @enumFromInt(falloff),
    );
}

/// Render a glow line segment.
export fn renderGlowLine(
    buffer: [*]watchface.color.Color,
    width: u32,
    height: u32,
    start_x: f32,
    start_y: f32,
    end_x: f32,
    end_y: f32,
    glow_width: f32,
    falloff: u8,
    color_r: f32,
    color_g: f32,
    color_b: f32,
) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    var ctx = watchface.band.Context{
        .buffer = buffer[0 .. w * h],
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };

    const segment = watchface.segment.Segment.init(
        watchface.vec2.xy(start_x, start_y),
        watchface.vec2.xy(end_x, end_y),
    );

    const config = watchface.glow.Config{
        .width = glow_width,
        .falloff = @enumFromInt(falloff),
        .color = .{ .uniform = watchface.color.rgba(color_r, color_g, color_b, 1) },
    };

    watchface.glow.renderLine(&ctx,segment, config, null, null);
}

// Rainbow palette (spectral colors)
const rainbow_colors = [7]watchface.color.Color{
    watchface.color.rgb(1.0, 0.2, 0.2), // Red
    watchface.color.rgb(1.0, 0.5, 0.1), // Orange
    watchface.color.rgb(1.0, 0.9, 0.2), // Yellow
    watchface.color.rgb(0.2, 0.9, 0.3), // Green
    watchface.color.rgb(0.2, 0.8, 0.9), // Cyan
    watchface.color.rgb(0.3, 0.4, 1.0), // Blue
    watchface.color.rgb(0.6, 0.2, 0.9), // Violet
};

/// Render the complete watchface with prism and rays based on time.
export fn renderWatchface(
    buffer: [*]watchface.color.Color,
    width: u32,
    height: u32,
    hours: f32,
    minutes: f32,
) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);
    const w_f: f32 = @floatFromInt(width);
    const h_f: f32 = @floatFromInt(height);

    var ctx = watchface.band.Context{
        .buffer = buffer[0 .. w * h],
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };

    ctx.clear();

    // Scene geometry
    const size = @min(w_f, h_f);
    const center = watchface.vec2.xy(w_f / 2.0, h_f / 2.0);
    const radius = size * 0.45;
    const prism_base = size * 0.28;

    const p = watchface.prism.Prism.init(center, prism_base);
    const bnd = watchface.boundary.Boundary.init(center, radius);

    // Compute ray paths from time
    const entry = watchface.clock.entryPoint(center, radius, minutes);
    const hour_angle = watchface.clock.hourAngle(hours, minutes);
    const rainbow_spread: f32 = 0.7;

    const paths = watchface.spectrum.Paths.compute(
        entry,
        hour_angle,
        rainbow_spread,
        p,
        bnd,
    );

    // Render prism glow
    const prism_color = watchface.color.rgba(0.6, 0.65, 0.8, 1);
    watchface.glow.renderPrismEdges(&ctx,p, prism_color, 80.0, 0.8, .exponential);

    // Glow config for rays
    const ray_width: f32 = 12.0;
    const falloff = watchface.glow.Falloff.quadratic;

    // Render entry ray (white)
    if (paths.entry_ray) |seg| {
        const entry_segment = watchface.segment.Segment.init(seg.start, seg.end);
        const entry_config = watchface.glow.Config{
            .width = ray_width,
            .falloff = falloff,
            .color = .{ .uniform = watchface.color.rgb(0.9, 0.9, 0.95) },
        };
        watchface.glow.renderLine(&ctx,entry_segment, entry_config, .{ .boundary = &bnd }, &p);
    }

    // Render each color band
    for (0..watchface.spectrum.band_count) |i| {
        const band = paths.bands[i];
        const band_color = rainbow_colors[i];

        // Internal segment 1 (white inside prism, or colored if no bounce)
        if (band.internal1) |seg| {
            const segment = watchface.segment.Segment.init(seg.start, seg.end);
            const internal_color = if (paths.needs_bounce)
                watchface.color.rgb(0.9, 0.9, 0.95)
            else
                band_color;
            const config = watchface.glow.Config{
                .width = ray_width * 0.8,
                .falloff = falloff,
                .color = .{ .uniform = internal_color },
            };
            watchface.glow.renderLine(&ctx,segment, config, .{ .prism = &p }, null);
        }

        // Internal segment 2 (colored, after bounce)
        if (band.internal2) |seg| {
            const segment = watchface.segment.Segment.init(seg.start, seg.end);
            const config = watchface.glow.Config{
                .width = ray_width * 0.8,
                .falloff = falloff,
                .color = .{ .uniform = band_color },
            };
            watchface.glow.renderLine(&ctx,segment, config, .{ .prism = &p }, null);
        }

        // Exit ray (colored, outside prism)
        if (band.exit_ray) |seg| {
            const segment = watchface.segment.Segment.init(seg.start, seg.end);
            const config = watchface.glow.Config{
                .width = ray_width,
                .falloff = falloff,
                .color = .{ .uniform = band_color },
            };
            watchface.glow.renderLine(&ctx,segment, config, .{ .boundary = &bnd }, &p);
        }
    }
}

// =============================================================================
// Full Watchface Rendering with Configuration
// =============================================================================

/// Render the complete watchface using configuration from JS.
/// This matches the C renderer's full feature set.
export fn renderWatchfaceWithConfig(
    buffer: [*]watchface.color.Color,
    out_rgba: [*]u8,
    width: u32,
    height: u32,
    config_ptr: *compat.WatchfaceConfig,
) void {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    // Re-initialize scene if dimensions changed
    if (!scene_initialized or w != last_width or h != last_height) {
        static_scene = watchface.scene.Scene.init(w, h);
        scene_initialized = true;
        last_width = w;
        last_height = h;
    }

    // Apply configuration
    const scene_config = compat.toSceneConfig(config_ptr);
    static_scene.setPrismConfig(scene_config.prism);
    static_scene.setGlowConfig(scene_config.glow_config);
    static_scene.setRayConfig(scene_config.ray);
    static_scene.setMarkerConfig(scene_config.marker);
    static_scene.setTime(config_ptr.hour, config_ptr.minute);

    // Create render context
    var ctx = watchface.band.Context{
        .buffer = buffer[0 .. w * h],
        .width = w,
        .height = h,
        .y_offset = 0,
        .total_height = h,
    };

    // Render scene (linear RGB)
    static_scene.renderBand(&ctx);

    // Apply gamma correction (linear -> sRGB)
    watchface.gamma.applyToBuffer(ctx.buffer);

    // Geometry for effects
    const grain_geometry = watchface.effect.grain.Geometry{
        .center_x = static_scene.center[0],
        .center_y = static_scene.center[1],
        .radius = static_scene.radius,
        .prism = static_scene.prism,
    };

    const vignette_geometry = watchface.effect.vignette.Geometry{
        .center_x = static_scene.center[0],
        .center_y = static_scene.center[1],
        .radius = static_scene.radius,
    };

    // Apply grain effect (in sRGB space)
    const grain_config = compat.toGrainConfig(&config_ptr.grain);
    if (grain_config.intensity > 0) {
        watchface.effect.grain.apply(ctx.buffer, w, h, grain_config, grain_geometry);
    }

    // Apply vignette effect (in sRGB space) - disabled when dithering is enabled
    if (config_ptr.dither.enabled == 0) {
        const vignette_config = compat.toVignetteConfig(&config_ptr.vignette);
        watchface.effect.vignette.apply(ctx.buffer, w, h, vignette_config, vignette_geometry);
    }

    // Handle dithering or direct output
    if (config_ptr.dither.enabled != 0) {
        applyDithering(ctx.buffer, out_rgba, w, h, &config_ptr.dither);
    } else {
        // Convert float buffer to RGBA bytes
        for (0..w * h) |i| {
            const out_idx = i * 4;
            out_rgba[out_idx] = floatToByte(ctx.buffer[i][0]);
            out_rgba[out_idx + 1] = floatToByte(ctx.buffer[i][1]);
            out_rgba[out_idx + 2] = floatToByte(ctx.buffer[i][2]);
            out_rgba[out_idx + 3] = 255;
        }
    }
}

fn applyDithering(
    buffer: []watchface.color.Color,
    out_rgba: [*]u8,
    width: usize,
    height: usize,
    dither_config: *const compat.SceneDitherConfig,
) void {
    const palette_type = compat.toDitherPaletteType(dither_config.mode);
    const palette_rgb = watchface.dither.getPalette(palette_type);
    const palette_cache = watchface.dither.PaletteCache.init(palette_rgb);

    const out_slice = out_rgba[0 .. width * height * 4];

    switch (dither_config.dither_type) {
        .error_diffusion => {
            const error_config = compat.toErrorDiffusionConfig(dither_config);

            // Use static preallocated error buffer
            if (width > max_dither_width) {
                directOutput(buffer, out_slice);
                return;
            }
            var err_buffer = watchface.dither.error_diffusion.ErrorBuffer.initStatic(&dither_error_backing, width);

            watchface.dither.error_diffusion.apply(
                buffer,
                out_slice,
                width,
                height,
                0,
                error_config,
                &palette_cache,
                &err_buffer,
            );
        },
        .ordered => {
            const ordered_config = compat.toOrderedDitherConfig(dither_config);
            watchface.dither.ordered.applyRgba(
                buffer,
                out_slice,
                width,
                height,
                ordered_config,
                &palette_cache,
            );
        },
    }
}

fn directOutput(buffer: []const watchface.color.Color, out_rgba: []u8) void {
    for (0..buffer.len) |i| {
        const out_idx = i * 4;
        out_rgba[out_idx] = floatToByte(buffer[i][0]);
        out_rgba[out_idx + 1] = floatToByte(buffer[i][1]);
        out_rgba[out_idx + 2] = floatToByte(buffer[i][2]);
        out_rgba[out_idx + 3] = 255;
    }
}

inline fn floatToByte(v: f32) u8 {
    @setFloatMode(.optimized);
    const clamped = @min(@max(v, 0.0), 1.0);
    return @intFromFloat(clamped * 255.0);
}
