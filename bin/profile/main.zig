const std = @import("std");

const lib = @import("lib");

const width = 256;
const height = 256;
const pixel_count = width * height;
const default_iteration_count = 100;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    const iteration_count = parseIterationCount();

    std.debug.print("{d} iterations at {d}x{d}\n", .{ iteration_count, width, height });

    var linear_buffer: [pixel_count]lib.Linear = undefined;
    var srgb_buffer: [pixel_count]lib.Srgb = undefined;
    var dither_error_buffer: [lib.Dither.errorBufferSize(width)]f32 = undefined;

    const config = lib.Config.init(allocator) catch @panic("failed to init config");

    const image = lib.Image.init(width, height);
    const viewport = image.viewport();

    const watchface = lib.Watchface{
        .hand_glow_normalized_width = config.hand_glow_normalized_width,
        .hand_glow_falloff = config.hand_glow_falloff,
        .hand_length_falloff = config.hand_length_falloff,
        .prism_glow_normalized_width = config.prism_glow_normalized_width,
        .prism_glow_falloff = config.prism_glow_falloff,
        .prism_glow_color = lib.Linear.init(0.5, 0.5, 0.5, 1.0),
        .rainbow_palette_id = config.dither_rainbow_palette_id,
    };

    const dither = lib.Dither{
        .normalized_strength = 0.8,
        .normalized_chroma_emphasis = 0.667,
        .palette = lib.Dither.PaletteId.ideal.palette(),
    };

    const grain = lib.Grain{ .normalized_deviation = config.grain_normalized_deviation };

    for (0..iteration_count) |iteration| {
        const hour: u32 = @intCast(iteration % 12);

        const minute: f32 = @as(f32, @floatFromInt(iteration)) * 60.0 /
            @as(f32, @floatFromInt(iteration_count));

        const clock = lib.Clock.init(
            lib.Time.init(hour, minute),
            config.prism_normalized_size,
            config.rainbow_normalized_spread,
        );

        @memset(&linear_buffer, lib.Linear.black);

        const linear_band = try image.band(lib.Linear, &linear_buffer, height, 0);

        watchface.render(linear_band, viewport, clock);

        const srgb_band = try dither.apply(linear_band, &srgb_buffer, &dither_error_buffer);

        grain.apply(srgb_band);

        if (config.background_enabled) {
            const crop = lib.Crop{ .outside_color = lib.Srgb.transparent, .antialias = true };

            crop.apply(srgb_band, viewport);
        }
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
