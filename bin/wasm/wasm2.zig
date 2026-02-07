const std = @import("std");
const allocator = std.heap.wasm_allocator;

const lib2 = @import("lib2");

const compat = @import("compat.zig");

var linear_colors: ?[]lib2.Linear = null;
var srgb_colors: ?[]lib2.Srgb = null;
var dither_error_buffer: ?[]f32 = null;
var last_width: usize = 0;
var last_height: usize = 0;

fn ensureBuffers(w: usize, h: usize) error{OutOfMemory}!void {
    if (w == last_width and h == last_height and
        linear_colors != null and srgb_colors != null and dither_error_buffer != null)
    {
        return;
    }

    if (linear_colors) |buf| allocator.free(buf);
    if (srgb_colors) |buf| allocator.free(buf);
    if (dither_error_buffer) |buf| allocator.free(buf);
    linear_colors = null;
    srgb_colors = null;
    dither_error_buffer = null;

    const pixel_count = w * h;

    linear_colors = try allocator.alloc(lib2.Linear, pixel_count);
    errdefer {
        allocator.free(linear_colors.?);
        linear_colors = null;
    }

    srgb_colors = try allocator.alloc(lib2.Srgb, pixel_count);
    errdefer {
        allocator.free(srgb_colors.?);
        srgb_colors = null;
    }

    dither_error_buffer = try allocator.alloc(f32, lib2.Dither.errorBufferSize(w));

    last_width = w;
    last_height = h;
}

export fn renderLib2WithConfig(
    width: u32,
    height: u32,
    config_ptr: *compat.WatchfaceConfig,
) ?[*]u8 {
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    ensureBuffers(w, h) catch return null;

    const time = lib2.Time.init(@intCast(config_ptr.hour), config_ptr.minute);

    const scene = lib2.Scene{
        .radius = 1.0,
        .prism = lib2.Prism.init(std.math.clamp(config_ptr.prism.size, 0.01, 1.0)),
        .normalized_rainbow_spread = std.math.clamp(config_ptr.prism.rainbow_spread, 0.0, 1.0),
    };
    const clock = lib2.Clock.init(time, scene);

    // Clear buffer to black
    const linear_buf = linear_colors.?;
    @memset(linear_buf, lib2.Linear.black);

    // Create full-image band and viewport
    const image = lib2.Image.init(w, h);
    var band = image.band(lib2.Linear, linear_buf, h, 0) catch return null;
    const viewport = image.viewport();

    const watchface = lib2.Watchface{
        .hand_glow_style = .{
            .width = config_ptr.ray.glow_width,
            .falloff = config_ptr.ray.falloff.toLib2(),
        },
        .prism_glow_style = .{
            .width = config_ptr.glow_config.width,
            .falloff = config_ptr.glow_config.falloff.toLib2(),
        },
        .prism_glow_color = lib2.Linear.init(
            @as(f32, @floatFromInt(config_ptr.glow_config.r)) / 255.0,
            @as(f32, @floatFromInt(config_ptr.glow_config.g)) / 255.0,
            @as(f32, @floatFromInt(config_ptr.glow_config.b)) / 255.0,
            1.0,
        ),
        .rainbow_palette_id = config_ptr.ray.ray_palette.toLib2(),
    };
    watchface.render(&band, viewport, scene, clock);

    const srgb_buf = srgb_colors.?;
    var srgb_band = if (config_ptr.dither.enabled != 0) blk: {
        const dither = lib2.Dither{
            .strength = config_ptr.dither.strength,
            .chroma_weight = config_ptr.dither.chroma_weight,
            .palette = config_ptr.dither.mode.toLib2().palette(),
        };
        break :blk dither.apply(band, srgb_buf, dither_error_buffer.?) catch return null;
    } else blk: {
        break :blk band.toSrgb(srgb_buf) catch return null;
    };

    if (config_ptr.dither.enabled == 0) {
        // Apply grain effect
        // TODO: UI should send grain scale in normalized coordinates so we can pass it directly
        const grain = lib2.Grain{
            .intensity = config_ptr.grain.intensity,
            .normalized_size = config_ptr.grain.scale * viewport.inverse_scale,
        };
        grain.apply(&srgb_band, viewport, scene.radius);
    }

    return @ptrCast(srgb_buf.ptr);
}
