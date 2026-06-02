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

    var config = try lib.Config.init(allocator);

    // The config default may enable grain; the PNG tool ignores it and applies a
    // texture only when explicitly requested via --grain or --dither.
    config.texture = if (args.dither) .dither else if (args.grain) .grain else .none;

    config.supersample_enabled = args.supersample;

    const supersample_factor = lib.frame.supersampleFactor(config);
    const linear_buffer = try allocator.alloc(lib.Linear, pixel_count * supersample_factor * supersample_factor);
    const srgb_buffer = try allocator.alloc(lib.Srgb, pixel_count);

    const error_buffer: ?[]f32 = if (config.texture == .dither)
        try allocator.alloc(f32, lib.dither.errorBufferSize(size))
    else
        null;

    const image = lib.Image.init(size, size);

    _ = try lib.frame.render(
        config,
        lib.Time.init(args.hour, @floatFromInt(args.minute)),
        image,
        linear_buffer,
        srgb_buffer,
        error_buffer,
    );

    try png.write(io, allocator, args.output_path, size, size, srgb_buffer);

    const texture_note = if (args.dither) " (dithered)" else if (args.grain) " (grain)" else "";

    std.debug.print("{d}x{d}{s} supersample={d}x -> {s}\n", .{
        size, size, texture_note, supersample_factor, args.output_path,
    });
}

const Args = struct {
    size: usize,
    hour: u32,
    minute: u32,
    output_path: []const u8,
    grain: bool,
    dither: bool,
    supersample: bool,
};

fn parseArgs(process_args: std.process.Args) ?Args {
    var arguments = process_args.iterate();

    _ = arguments.next(); // skip program name

    var positional: [4][]const u8 = undefined;
    var positional_count: usize = 0;
    var grain = false;
    var dither = false;
    var supersample = false;
    var options_ended = false;

    while (arguments.next()) |arg| {
        if (!options_ended and std.mem.eql(u8, arg, "--")) {
            options_ended = true;
        } else if (!options_ended and std.mem.eql(u8, arg, "--grain")) {
            grain = true;
        } else if (!options_ended and std.mem.eql(u8, arg, "--dither")) {
            dither = true;
        } else if (!options_ended and std.mem.eql(u8, arg, "--supersample")) {
            supersample = true;
        } else if (!options_ended and std.mem.startsWith(u8, arg, "--")) {
            return null;
        } else {
            if (positional_count == positional.len) return null;

            positional[positional_count] = arg;
            positional_count += 1;
        }
    }

    if (positional_count != positional.len) return null;

    if (grain and dither) return null;

    const size = std.fmt.parseInt(usize, positional[0], 10) catch return null;
    const hour = std.fmt.parseInt(u32, positional[1], 10) catch return null;
    const minute = std.fmt.parseInt(u32, positional[2], 10) catch return null;

    if (size == 0 or hour > 23 or minute > 59) return null;

    // Reject sizes whose pixel count (size * size) would overflow usize.
    if (@mulWithOverflow(size, size)[1] != 0) return null;

    return .{
        .size = size,
        .hour = hour,
        .minute = minute,
        .output_path = positional[3],
        .grain = grain,
        .dither = dither,
        .supersample = supersample,
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: png <size> <hour> <minute> <output.png> [--grain | --dither] [--supersample]
        \\
        \\  size           Image size in pixels (square, diameter of the unit circle)
        \\  hour           Hour (0-23)
        \\  minute         Minute (0-59)
        \\  output.png     Output file path
        \\  --grain        Add film grain to the full-colour output
        \\  --dither       Quantize the output to the Pebble 64-colour cube
        \\  --supersample  Render 2x2 and box-average down to antialias edges (off by default)
        \\
        \\--grain and --dither are mutually exclusive; without either, no texture is applied.
        \\
    , .{});
}
