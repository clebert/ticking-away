const std = @import("std");

const lib = @import("lib");

const png = @import("png.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = parseArgs(init.minimal.args) orelse {
        printUsage();
        std.process.exit(1);
    };

    const size = args.size;
    const pixel_count = size * size;

    const linear_buffer = try allocator.alloc(lib.Linear, pixel_count);
    const srgb_buffer = try allocator.alloc(lib.Srgb, pixel_count);

    const config = try lib.Config.init(allocator);
    const image = lib.Image.init(size, size);

    // The PNG export is a full-color renderer; the palette-quantizing dither
    // is intentionally never applied, so no error buffer is passed.
    _ = try lib.frame.render(
        config,
        lib.Time.init(args.hour, @floatFromInt(args.minute)),
        image,
        linear_buffer,
        srgb_buffer,
        null,
    );

    try png.write(io, allocator, args.output_path, size, size, srgb_buffer);

    std.debug.print("{d}x{d} -> {s}\n", .{ size, size, args.output_path });
}

const Args = struct {
    size: usize,
    hour: u32,
    minute: u32,
    output_path: []const u8,
};

fn parseArgs(process_args: std.process.Args) ?Args {
    var arguments = process_args.iterate();

    _ = arguments.next(); // skip program name

    const size_str = arguments.next() orelse return null;
    const hour_str = arguments.next() orelse return null;
    const minute_str = arguments.next() orelse return null;
    const output_path = arguments.next() orelse return null;

    const size = std.fmt.parseInt(usize, size_str, 10) catch return null;
    const hour = std.fmt.parseInt(u32, hour_str, 10) catch return null;
    const minute = std.fmt.parseInt(u32, minute_str, 10) catch return null;

    if (size == 0 or hour > 23 or minute > 59) return null;

    return .{
        .size = size,
        .hour = hour,
        .minute = minute,
        .output_path = output_path,
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: png <size> <hour> <minute> <output.png>
        \\
        \\  size        Image size in pixels (square, diameter of the unit circle)
        \\  hour        Hour (0-23)
        \\  minute      Minute (0-59)
        \\  output.png  Output file path
        \\
    , .{});
}
