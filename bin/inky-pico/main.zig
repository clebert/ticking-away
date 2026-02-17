const std = @import("std");
const build_options = @import("build_options");

const lib = @import("lib");

const display = @import("display.zig");
const hal = @import("hal.zig");

const display_width = 1200;
const display_height = 1600;
const controller_columns = 600;
const band_height = 1;
const band_count = display_height / band_height;
const band_pixels = display_width * band_height;
const packed_row_bytes = controller_columns / 2;

/// Maps Dither palette index (0-5) to display color value (skipping 4).
const display_values = [6]u8{ 0, 1, 2, 3, 5, 6 };

const interval_ms: u64 = 5 * 60 * 1000;

comptime {
    _ = @import("boot.zig");
}

var parse_buffer: [4096]u8 = undefined;

/// Single-shot render cycle: render watchface, refresh display, then sleep until next update.
pub fn main() void {
    hal.initClocks();
    hal.initSpi();

    // Preserve time across warm reboots (AIRCR reset after dormant wake)
    if (!hal.isTimerRunning()) {
        hal.setTimeMs(build_options.initial_utc_time_ms);
        hal.startTimer();
    }

    hal.useXosc();
    hal.calibrateLposc();

    const time = readTime();

    var fixed_buffer = std.heap.FixedBufferAllocator.init(&parse_buffer);

    const config = lib.Config.init(fixed_buffer.allocator()) catch unreachable;

    const watchface = lib.Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .hand_glow_falloff = config.hand_glow_falloff,
        .hand_length_falloff = config.hand_length_falloff,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .prism_glow_falloff = config.prism_glow_falloff,
        .prism_glow_color = lib.Linear.init(0.1, config.prism_glow_linear_green, 1.0, 1.0),
        .rainbow_palette_id = config.rainbow_palette_id,
    };

    const dither = lib.Dither{
        .normalized_strength = config.dither_normalized_strength,
        .normalized_chroma_emphasis = config.dither_normalized_chroma_emphasis,
        .palette = config.dither_palette_id.palette(),
    };

    const image = lib.Image.init(display_width, display_height);
    const viewport = image.viewportRotated(.clockwise_90);

    const minute = snapMinute(time.minute, 5);

    const clock = lib.Clock.init(
        lib.Time.init(time.hour, @floatFromInt(minute)),
        config.prism_normalized_size,
        config.rainbow_normalized_spread,
    );

    const crop: ?lib.Crop = if (config.background_enabled) .{
        .outside_color = dither.palette.white(),
    } else null;

    display.init();
    render(watchface, dither, crop, image, viewport, clock);
    display.refresh();

    // Set alarm for next update and enter dormant
    const now_ms = hal.readTimeMs();

    hal.setAlarm(now_ms + interval_ms);
    hal.useLposc();
    hal.enterDormant();

    // Execution resumes here after dormant wake — soft reset to re-run from boot
    hal.softReset();
}

fn render(
    watchface: lib.Watchface,
    dither: lib.Dither,
    crop: ?lib.Crop,
    image: lib.Image,
    viewport: lib.Image.Viewport(.clockwise_90),
    clock: lib.Clock,
) void {
    var linear_buffer: [band_pixels]lib.Linear = undefined;
    var srgb_buffer: [band_pixels]lib.Srgb = undefined;
    var error_buffer: [lib.Dither.errorBufferSize(display_width)]f32 = undefined;
    var pack_row: [packed_row_bytes]u8 = undefined;

    for ([_]display.ChipSelect{ .cs0, .cs1 }, [_]usize{ 0, controller_columns }) |cs, column_offset| {
        @memset(&error_buffer, 0);
        display.beginData(cs);

        for (0..band_count) |band_index| {
            @memset(&linear_buffer, lib.Linear.black);

            const linear_band = image.band(lib.Linear, &linear_buffer, band_height, band_index) catch unreachable;

            watchface.render(linear_band, viewport, clock);

            const srgb_band = dither.apply(linear_band, &srgb_buffer, &error_buffer) catch unreachable;

            if (crop) |c| c.apply(srgb_band, viewport);

            packRow(&srgb_band, dither.palette, column_offset, &pack_row);

            display.writeData(&pack_row);
        }

        display.endData();
    }
}

fn packRow(
    band: *const lib.Image.Band(lib.Srgb),
    palette: lib.Dither.Palette,
    column_offset: usize,
    pack_buffer: *[packed_row_bytes]u8,
) void {
    for (0..packed_row_bytes) |i| {
        const x0 = column_offset + i * 2;
        const x1 = x0 + 1;

        const value0 = display_values[paletteIndex(band.colorAt(x0, 0).*, palette)];
        const value1 = display_values[paletteIndex(band.colorAt(x1, 0).*, palette)];

        pack_buffer[i] = (value0 << 4) | value1;
    }
}

fn paletteIndex(pixel: lib.Srgb, palette: lib.Dither.Palette) usize {
    for (palette.srgb_colors, 0..) |color, i| {
        if (pixel.r == color.r and pixel.g == color.g and pixel.b == color.b) {
            return i;
        }
    }

    return 0;
}

const LocalTime = struct {
    hour: u32,
    minute: u32,
};

fn readTime() LocalTime {
    const ms = hal.readTimeMs();
    const offset_ms: i64 = build_options.utc_offset_ms;
    const local_ms: u64 = @intCast(@as(i64, @intCast(ms)) + offset_ms);
    const total_seconds = local_ms / 1000;
    const day_seconds = total_seconds % (24 * 3600);

    return .{
        .hour = @intCast((day_seconds / 3600) % 12),
        .minute = @intCast((day_seconds % 3600) / 60),
    };
}

fn snapMinute(minute: u32, interval: u32) u32 {
    return minute - (minute % interval);
}
