const std = @import("std");

const watchface = @import("watchface");

// =============================================================================
// WASM Memory Management
// =============================================================================

extern var __heap_base: u8;

export fn getHeapBase() [*]u8 {
    return @ptrCast(&__heap_base);
}

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
    const segment = watchface.line.Segment.init(
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

    ctx.renderGlowLine(segment, config, null, null);
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

    // Create centered isosceles triangle at 50% viewport size
    const center = watchface.vec2.xy(w_f / 2, h_f / 2);
    const base_width = @min(w_f, h_f) * 0.5;
    const tri = watchface.triangle.Triangle.isosceles(center, base_width, 60);

    ctx.renderPrismGlow(
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

    const segment = watchface.line.Segment.init(
        watchface.vec2.xy(start_x, start_y),
        watchface.vec2.xy(end_x, end_y),
    );

    const config = watchface.glow.Config{
        .width = glow_width,
        .falloff = @enumFromInt(falloff),
        .color = .{ .uniform = watchface.color.rgba(color_r, color_g, color_b, 1) },
    };

    ctx.renderGlowLine(segment, config, null, null);
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

    const prism = watchface.triangle.Triangle.isosceles(center, prism_base, 60);
    const boundary = watchface.circle.Circle.init(center, radius);

    // Compute ray paths from time
    const entry = watchface.clock.entryPoint(center, radius, minutes);
    const hour_angle = watchface.clock.hourAngle(hours, minutes);
    const rainbow_spread: f32 = 0.7;

    const paths = watchface.spectrum.Paths.compute(
        entry,
        hour_angle,
        rainbow_spread,
        prism,
        boundary,
    );

    // Render prism glow
    const prism_color = watchface.color.rgba(0.6, 0.65, 0.8, 1);
    ctx.renderPrismGlow(prism, prism_color, 80.0, 0.8, .exponential);

    // Glow config for rays
    const ray_width: f32 = 12.0;
    const falloff = watchface.glow.Falloff.quadratic;

    // Render entry ray (white)
    if (paths.entry_ray) |seg| {
        const entry_segment = watchface.line.Segment.init(seg.start, seg.end);
        const entry_config = watchface.glow.Config{
            .width = ray_width,
            .falloff = falloff,
            .color = .{ .uniform = watchface.color.rgb(0.9, 0.9, 0.95) },
        };
        ctx.renderGlowLine(entry_segment, entry_config, .{ .circle = &boundary }, &prism);
    }

    // Render each color band
    for (0..watchface.spectrum.band_count) |i| {
        const band = paths.bands[i];
        const band_color = rainbow_colors[i];

        // Internal segment 1 (white inside prism, or colored if no bounce)
        if (band.internal1) |seg| {
            const segment = watchface.line.Segment.init(seg.start, seg.end);
            const internal_color = if (paths.needs_bounce)
                watchface.color.rgb(0.9, 0.9, 0.95)
            else
                band_color;
            const config = watchface.glow.Config{
                .width = ray_width * 0.8,
                .falloff = falloff,
                .color = .{ .uniform = internal_color },
            };
            ctx.renderGlowLine(segment, config, .{ .triangle = &prism }, null);
        }

        // Internal segment 2 (colored, after bounce)
        if (band.internal2) |seg| {
            const segment = watchface.line.Segment.init(seg.start, seg.end);
            const config = watchface.glow.Config{
                .width = ray_width * 0.8,
                .falloff = falloff,
                .color = .{ .uniform = band_color },
            };
            ctx.renderGlowLine(segment, config, .{ .triangle = &prism }, null);
        }

        // Exit ray (colored, outside prism)
        if (band.exit_ray) |seg| {
            const segment = watchface.line.Segment.init(seg.start, seg.end);
            const config = watchface.glow.Config{
                .width = ray_width,
                .falloff = falloff,
                .color = .{ .uniform = band_color },
            };
            ctx.renderGlowLine(segment, config, .{ .circle = &boundary }, &prism);
        }
    }
}
