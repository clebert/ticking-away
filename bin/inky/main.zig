const std = @import("std");

const lib = @import("lib");

const spi = @import("spi.zig");

const display_width = 1200;
const display_height = 1600;
const controller_columns = 600;
const band_height = 1;
const band_count = display_height / band_height;
const band_pixels = display_width * band_height;
const packed_row_bytes = controller_columns / 2;

/// Maps Dither palette index (0-5) to display color value (skipping 4).
const display_values = [6]u8{ 0, 1, 2, 3, 5, 6 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    const args = parseArgs() orelse {
        printUsage();
        std.process.exit(1);
    };

    const tz = blk: {
        const file = try std.fs.openFileAbsolute("/etc/localtime", .{});

        defer file.close();

        const data = try file.readToEndAlloc(allocator, 1 << 16);

        var stream = std.io.fixedBufferStream(data);

        break :blk try std.Tz.parse(allocator, stream.reader());
    };

    var config = try lib.Config.init(allocator);

    config.prism_normalized_size = args.prism_size;
    config.rainbow_normalized_spread = args.rainbow_spread;
    config.rainbow_palette_id = args.rainbow_palette_id;
    config.dither_palette_id = args.dither_palette_id;
    config.dither_normalized_strength = args.dither_strength;
    config.dither_normalized_chroma_emphasis = args.dither_chroma;

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

    var display = try spi.Display.init();

    defer display.deinit();

    while (true) {
        const now = try localTime(tz);
        const minute = snapMinute(now.minute, args.interval);

        std.debug.print("{d:0>2}:{d:0>2}\n", .{ now.hour, minute });

        const clock = lib.Clock.init(
            lib.Time.init(now.hour, @floatFromInt(minute)),
            config.prism_normalized_size,
            config.rainbow_normalized_spread,
        );

        const crop: ?lib.Crop = if (args.background_enabled)
            .{ .outside_color = dither.palette.white() }
        else
            null;

        try render(&display, watchface, dither, crop, image, viewport, clock);
        try display.refresh();

        sleepUntilNext(now.minute, now.second, args.interval);
    }
}

fn render(
    display: *spi.Display,
    watchface: lib.Watchface,
    dither: lib.Dither,
    crop: ?lib.Crop,
    image: lib.Image,
    viewport: lib.Image.Viewport(.clockwise_90),
    clock: lib.Clock,
) !void {
    var linear_buffer: [band_pixels]lib.Linear = undefined;
    var srgb_buffer: [band_pixels]lib.Srgb = undefined;
    var error_buffer: [lib.Dither.errorBufferSize(display_width)]f32 = undefined;
    var pack_row: [packed_row_bytes]u8 = undefined;

    for ([_]spi.ChipSelect{ .cs0, .cs1 }, [_]usize{ 0, controller_columns }) |cs, column_offset| {
        @memset(&error_buffer, 0);
        try display.beginData(cs);

        for (0..band_count) |band_index| {
            @memset(&linear_buffer, lib.Linear.black);

            const linear_band = try image.band(lib.Linear, &linear_buffer, band_height, band_index);

            watchface.render(linear_band, viewport, clock);

            const srgb_band = try dither.apply(linear_band, &srgb_buffer, &error_buffer);

            if (crop) |c| c.apply(srgb_band, viewport);

            packRow(&srgb_band, dither.palette, column_offset, &pack_row);

            try display.writeData(&pack_row);
        }

        try display.endData();
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
    second: u32,
};

fn localTime(tz: std.Tz) !LocalTime {
    const epoch = try std.posix.clock_gettime(.REALTIME);
    const utc_seconds: i64 = epoch.sec;
    const offset: i64 = utcOffset(tz, utc_seconds);
    const local_seconds: u64 = @intCast(utc_seconds + offset);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = local_seconds };
    const day_seconds = epoch_seconds.getDaySeconds();

    return .{
        .hour = day_seconds.getHoursIntoDay() % 12,
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

fn utcOffset(tz: std.Tz, utc_seconds: i64) i64 {
    var offset: i32 = 0;

    for (tz.transitions) |transition| {
        if (transition.ts > utc_seconds) break;

        offset = transition.timetype.offset;
    }

    return offset;
}

/// Snap a minute value down to the nearest interval boundary.
fn snapMinute(minute: u32, interval: u32) u32 {
    return minute - (minute % interval);
}

/// Sleep until the next interval boundary.
fn sleepUntilNext(current_minute: u32, current_second: u32, interval: u32) void {
    const next_minute = snapMinute(current_minute, interval) + interval;
    const remaining_seconds = (next_minute - current_minute) * 60 - current_second;

    std.posix.nanosleep(@intCast(remaining_seconds), 0);
}

const Args = struct {
    interval: u32 = 1,
    rainbow_palette_id: lib.Rainbow.PaletteId = .spectra6,
    dither_palette_id: lib.Dither.PaletteId = .spectra6_epdopt,
    dither_strength: f32 = 0.9,
    dither_chroma: f32 = 0.5,
    prism_size: f32 = 1.0,
    rainbow_spread: f32 = 1.0,
    background_enabled: bool = false,
};

fn parseArgs() ?Args {
    var arguments = std.process.args();

    _ = arguments.next(); // skip program name

    var args = Args{};

    while (arguments.next()) |arg| {
        if (std.mem.eql(u8, arg, "--interval")) {
            const value = arguments.next() orelse return null;

            args.interval = std.fmt.parseInt(u32, value, 10) catch return null;

            if (args.interval == 0 or args.interval > 60 or 60 % args.interval != 0) return null;
        } else if (std.mem.eql(u8, arg, "--rainbow-palette")) {
            const value = arguments.next() orelse return null;

            args.rainbow_palette_id = std.meta.stringToEnum(lib.Rainbow.PaletteId, value) orelse return null;
        } else if (std.mem.eql(u8, arg, "--dither-palette")) {
            const value = arguments.next() orelse return null;

            args.dither_palette_id = std.meta.stringToEnum(lib.Dither.PaletteId, value) orelse return null;
        } else if (std.mem.eql(u8, arg, "--dither-strength")) {
            const value = arguments.next() orelse return null;

            args.dither_strength = std.fmt.parseFloat(f32, value) catch return null;

            if (args.dither_strength < 0.0 or args.dither_strength > 1.0) return null;
        } else if (std.mem.eql(u8, arg, "--dither-chroma")) {
            const value = arguments.next() orelse return null;

            args.dither_chroma = std.fmt.parseFloat(f32, value) catch return null;

            if (args.dither_chroma < 0.0 or args.dither_chroma > 1.0) return null;
        } else if (std.mem.eql(u8, arg, "--rainbow-spread")) {
            const value = arguments.next() orelse return null;

            args.rainbow_spread = std.fmt.parseFloat(f32, value) catch return null;

            if (args.rainbow_spread < 0.0 or args.rainbow_spread > 1.0) return null;
        } else if (std.mem.eql(u8, arg, "--prism-size")) {
            const value = arguments.next() orelse return null;

            args.prism_size = std.fmt.parseFloat(f32, value) catch return null;

            if (args.prism_size < 0.0 or args.prism_size > 1.0) return null;
        } else if (std.mem.eql(u8, arg, "--background")) {
            args.background_enabled = true;
        } else {
            return null;
        }
    }

    return args;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: inky [options]
        \\
        \\  --interval <minutes>    Update interval (default: 1)
        \\                          Must evenly divide 60 (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60)
        \\  --rainbow-palette <id>  Rainbow palette (default: spectra6)
        \\                          oklch_balanced, spectral, spectra6
        \\  --dither-palette <id>   Dither palette (default: spectra6_epdopt)
        \\                          ideal, spectra6_inky, spectra6_epdopt, spectra6_trmnl
        \\  --dither-strength <n>   Dither strength 0.0-1.0 (default: 0.9)
        \\  --dither-chroma <n>     Dither chroma emphasis 0.0-1.0 (default: 0.5)
        \\  --rainbow-spread <n>    Rainbow spread 0.0-1.0 (default: 1.0)
        \\  --prism-size <n>        Prism size 0.0-1.0 (default: 1.0)
        \\  --background            Enable circular crop with white background
        \\
    , .{});
}
