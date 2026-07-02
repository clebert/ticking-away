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

    config.texture = args.texture;

    config.ray_style = if (args.sharp) .sharp else .glow;

    const linear_buffer = try allocator.alloc(lib.Linear, pixel_count);
    const srgb_buffer = try allocator.alloc(lib.Srgb, pixel_count);

    const error_buffer: ?[]f32 = switch (config.texture) {
        .dither_pebble => try allocator.alloc(f32, lib.dither_pebble.errorBufferSize(size)),
        .dither_trmnl => try allocator.alloc(f32, lib.dither_trmnl.errorBufferSize(size)),
        .grain, .none => null,
    };

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

    const texture_note = switch (args.texture) {
        .dither_pebble => " (pebble dither)",
        .dither_trmnl => " (trmnl dither)",
        .grain => " (grain)",
        .none => "",
    };

    std.debug.print("{d}x{d}{s} -> {s}\n", .{
        size, size, texture_note, args.output_path,
    });
}

const Args = struct {
    size: usize,
    hour: u32,
    minute: u32,
    output_path: []const u8,
    texture: lib.Config.Texture,
    sharp: bool,
};

fn parseArgs(process_args: std.process.Args) ?Args {
    var arguments = process_args.iterate();

    _ = arguments.next();

    var positional: [4][]const u8 = undefined;
    var positional_count: usize = 0;
    var texture: ?lib.Config.Texture = null;
    var sharp = false;
    var options_ended = false;

    while (arguments.next()) |arg| {
        if (!options_ended and std.mem.eql(u8, arg, "--")) {
            options_ended = true;
        } else if (!options_ended and std.mem.eql(u8, arg, "--grain")) {
            if (texture != null) return null;
            texture = .grain;
        } else if (!options_ended and std.mem.eql(u8, arg, "--dither-pebble")) {
            if (texture != null) return null;
            texture = .dither_pebble;
        } else if (!options_ended and std.mem.eql(u8, arg, "--dither-trmnl")) {
            if (texture != null) return null;
            texture = .dither_trmnl;
        } else if (!options_ended and std.mem.eql(u8, arg, "--sharp")) {
            sharp = true;
        } else if (!options_ended and std.mem.startsWith(u8, arg, "--")) {
            return null;
        } else {
            if (positional_count == positional.len) return null;

            positional[positional_count] = arg;
            positional_count += 1;
        }
    }

    if (positional_count != positional.len) return null;

    const size = std.fmt.parseInt(usize, positional[0], 10) catch return null;
    const hour = std.fmt.parseInt(u32, positional[1], 10) catch return null;
    const minute = std.fmt.parseInt(u32, positional[2], 10) catch return null;

    if (size == 0 or hour > 23 or minute > 59) return null;

    if (@mulWithOverflow(size, size)[1] != 0) return null;

    return .{
        .size = size,
        .hour = hour,
        .minute = minute,
        .output_path = positional[3],
        .texture = texture orelse .none,
        .sharp = sharp,
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: png <size> <hour> <minute> <output.png> [--grain | --dither-pebble | --dither-trmnl] [--sharp]
        \\
        \\  size            Image size in pixels (square, diameter of the unit circle)
        \\  hour            Hour (0-23)
        \\  minute          Minute (0-59)
        \\  output.png      Output file path
        \\  --grain         Add film grain to the full-colour output
        \\  --dither-pebble Quantize the output to the Pebble 64-colour cube
        \\  --dither-trmnl  Quantize the output to the TRMNL e-ink four greyscale levels
        \\  --sharp         Album-cover look: no glow, solid rainbow bands, crisp rays
        \\
        \\The texture flags are mutually exclusive; without any, no texture is applied.
        \\
    , .{});
}
