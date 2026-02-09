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

    // Render watchface with default settings matching src/stores.ts

    const image = lib.Image.init(size, size);
    const viewport = image.viewport();
    const prism = lib.Prism.init(0.9);
    const time = lib.Time.init(args.hour, @floatFromInt(args.minute));
    const clock = lib.Clock.init(time, prism, 0.5);

    @memset(linear_buffer, lib.Linear.black);

    var linear_band = image.band(lib.Linear, linear_buffer, size, 0) catch unreachable;

    const watchface = lib.Watchface{
        .hand_glow_style = .{ .normalized_width = 0.01, .falloff = .exponential },
        .prism_glow_style = .{ .normalized_width = 0.07, .falloff = .exponential },
        .prism_glow_color = lib.Linear.init(0.1, 0.75, 1.0, 1.0),
        .rainbow_palette_id = .oklch_balanced,
    };

    watchface.render(&linear_band, viewport, prism, clock);

    var srgb_band = linear_band.toSrgb(srgb_buffer) catch unreachable;

    const grain = lib.Grain{
        .normalized_deviation = 0.1,
    };

    grain.apply(&srgb_band, viewport);

    const crop = lib.Crop{ .outside_color = lib.Srgb.transparent };

    crop.apply(&srgb_band, viewport);

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
