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
    const segment = watchface.line.Segment{
        .start = watchface.vec2.xy(0, 0),
        .end = watchface.vec2.xy(@floatFromInt(width), @floatFromInt(height)),
    };

    const config = watchface.glow.Config{
        .width = 5,
        .falloff = .exponential,
        .color = watchface.color.white,
    };

    ctx.renderGlowLine(segment, config);
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

    const segment = watchface.line.Segment{
        .start = watchface.vec2.xy(start_x, start_y),
        .end = watchface.vec2.xy(end_x, end_y),
    };

    const config = watchface.glow.Config{
        .width = glow_width,
        .falloff = @enumFromInt(falloff),
        .color = .{ color_r, color_g, color_b, 1 },
    };

    ctx.renderGlowLine(segment, config);
}
