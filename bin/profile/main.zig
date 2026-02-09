const std = @import("std");

const lib = @import("lib");

const width = 256;
const height = 256;
const pixel_count = width * height;
const default_iteration_count = 100;

pub fn main() void {
    const iteration_count = parseIterationCount();

    std.debug.print("{d} iterations at {d}x{d}\n", .{ iteration_count, width, height });

    var linear_buffer: [pixel_count]lib.Linear = undefined;
    var srgb_buffer: [pixel_count]lib.Srgb = undefined;
    var dither_error_buffer: [lib.Dither.errorBufferSize(width)]f32 = undefined;

    const image = lib.Image.init(width, height);
    const viewport = image.viewport();
    const prism = lib.Prism.init(0.8);

    const watchface = lib.Watchface{
        .hand_glow_style = .{ .normalized_width = 0.08, .falloff = .quadratic },
        .prism_glow_style = .{ .normalized_width = 0.15, .falloff = .quadratic },
        .prism_glow_color = lib.Linear.init(0.5, 0.5, 0.5, 1.0),
        .rainbow_palette_id = .oklch_balanced,
    };

    const dither = lib.Dither{
        .normalized_strength = 0.8,
        .normalized_chroma_emphasis = 0.667,
        .palette = lib.Dither.PaletteId.ideal.palette(),
    };

    const grain = lib.Grain{
        .normalized_deviation = 0.1,
    };

    for (0..iteration_count) |iteration| {
        const hour: u32 = @intCast(iteration % 12);

        const minute: f32 = @as(f32, @floatFromInt(iteration)) * 60.0 /
            @as(f32, @floatFromInt(iteration_count));

        const time = lib.Time.init(hour, minute);
        const clock = lib.Clock.init(time, prism, 0.5);

        @memset(&linear_buffer, lib.Linear.black);

        var linear_band = image.band(lib.Linear, &linear_buffer, height, 0) catch unreachable;

        watchface.render(&linear_band, viewport, prism, clock);

        var srgb_band = dither.apply(linear_band, &srgb_buffer, &dither_error_buffer) catch unreachable;

        grain.apply(&srgb_band, viewport);

        const crop = lib.Crop{ .outside_color = lib.Srgb.transparent };

        crop.apply(&srgb_band, viewport);
    }
}

fn parseIterationCount() usize {
    var arguments = std.process.args();

    _ = arguments.next();

    const count_string = arguments.next() orelse return default_iteration_count;

    return std.fmt.parseInt(usize, count_string, 10) catch {
        std.debug.print("Usage: profile [iteration_count]\n", .{});
        std.process.exit(1);
    };
}
