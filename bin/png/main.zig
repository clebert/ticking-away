const std = @import("std");

const lib = @import("lib");

const png = @import("png.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    const args = parseArgs() orelse {
        printUsage();
        std.process.exit(1);
    };

    const size = args.height;
    const pixel_count = size * size;

    const linear_buffer = try allocator.alloc(lib.Linear, pixel_count);
    const srgb_buffer = try allocator.alloc(lib.Srgb, pixel_count);

    const config = try lib.Config.init(allocator);

    const image = lib.Image.init(size, size);
    const viewport = image.viewport();

    const clock = lib.Clock.init(
        lib.Time.init(args.hour, @floatFromInt(args.minute)),
        config.prism_normalized_size,
        config.rainbow_normalized_spread,
    );

    @memset(
        linear_buffer,
        if (config.background_enabled) lib.Linear.black else lib.Linear.transparent,
    );

    const linear_band = try image.band(lib.Linear, linear_buffer, size, 0);

    const watchface = lib.Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .hand_glow_falloff = config.hand_glow_falloff,
        .hand_length_falloff = config.hand_length_falloff,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .prism_glow_falloff = config.prism_glow_falloff,
        .prism_glow_color = lib.Linear.init(0.1, config.prism_glow_linear_green, 1.0, 1.0),
        .rainbow_palette_id = config.rainbow_palette_id,
    };

    watchface.render(linear_band, viewport, clock);

    const srgb_band = try linear_band.toSrgb(srgb_buffer);

    if (config.grain_enabled) {
        const grain = lib.Grain{ .normalized_deviation = config.grain_normalized_deviation };

        grain.apply(srgb_band);
    }

    if (config.background_enabled) {
        const crop = lib.Crop{ .outside_color = lib.Srgb.transparent };

        crop.apply(srgb_band, viewport);
    }

    try png.write(allocator, args.output_path, size, size, srgb_buffer);

    std.debug.print("{d}x{d} -> {s}\n", .{ size, size, args.output_path });
}

const Args = struct {
    height: usize,
    hour: u32,
    minute: u32,
    output_path: []const u8,
};

fn parseArgs() ?Args {
    var arguments = std.process.args();

    _ = arguments.next(); // skip program name

    const height_str = arguments.next() orelse return null;
    const hour_str = arguments.next() orelse return null;
    const minute_str = arguments.next() orelse return null;
    const output_path = arguments.next() orelse return null;

    const height = std.fmt.parseInt(usize, height_str, 10) catch return null;
    const hour = std.fmt.parseInt(u32, hour_str, 10) catch return null;
    const minute = std.fmt.parseInt(u32, minute_str, 10) catch return null;

    if (height == 0 or hour > 23 or minute > 59) return null;

    return .{
        .height = height,
        .hour = hour % 12,
        .minute = minute,
        .output_path = output_path,
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: png <height> <hour> <minute> <output.png>
        \\
        \\  height      Image size in pixels (square, diameter of the unit circle)
        \\  hour        Hour (0-23)
        \\  minute      Minute (0-59)
        \\  output.png  Output file path
        \\
    , .{});
}
