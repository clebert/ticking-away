const std = @import("std");

const lib2 = @import("lib2");

const width: usize = 390;
const height: usize = 390;
const max_frames: usize = 720;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = std.process.args();
    _ = args.skip();

    const total_frames: usize = if (args.next()) |arg|
        std.fmt.parseInt(usize, arg, 10) catch {
            std.debug.print("Usage: perf-lib2 [frames]\n", .{});
            std.debug.print("  frames: number of frames to render (1-720, default: 720)\n", .{});
            return;
        }
    else
        max_frames;

    if (total_frames == 0 or total_frames > max_frames) {
        std.debug.print("Error: frames must be between 1 and {d}\n", .{max_frames});
        return;
    }

    const pixel_count = width * height;
    const linear_buf = try allocator.alloc(lib2.Linear, pixel_count);
    defer allocator.free(linear_buf);

    const srgb_buf = try allocator.alloc(lib2.Srgb, pixel_count);
    defer allocator.free(srgb_buf);

    const frame_times = try allocator.alloc(u64, total_frames);
    defer allocator.free(frame_times);

    const render_times = try allocator.alloc(u64, total_frames);
    defer allocator.free(render_times);

    const srgb_times = try allocator.alloc(u64, total_frames);
    defer allocator.free(srgb_times);

    const grain_times = try allocator.alloc(u64, total_frames);
    defer allocator.free(grain_times);

    const image = lib2.Image.init(width, height);
    const viewport = image.viewport();

    const scene = lib2.Scene{
        .radius = 1.0,
        .prism = lib2.Prism.init(0.8),
        .normalized_rainbow_spread = 0.5,
    };

    const watchface = lib2.Watchface{
        .hand_glow_style = .{ .width = 0.08, .falloff = .quadratic },
        .prism_glow_style = .{ .width = 0.15, .falloff = .quadratic },
        .prism_glow_color = lib2.Linear.init(0.3, 0.3, 0.4, 1.0),
        .rainbow_palette_id = .spectral,
    };

    std.debug.print("Resolution: {d}x{d}, frames: {d}\n", .{ width, height, total_frames });

    var timer = try std.time.Timer.start();
    const start_total = timer.read();

    for (0..total_frames) |frame_idx| {
        const hour = frame_idx / 60;
        const minute = frame_idx % 60;
        const time = lib2.Time.init(@intCast(hour), @floatFromInt(minute));

        const frame_start = timer.read();

        const clock = lib2.Clock.init(time, scene);

        @memset(linear_buf, lib2.Linear.black);

        var band = image.band(lib2.Linear, linear_buf, height, 0) catch continue;

        watchface.render(&band, viewport, scene, clock);

        const render_end = timer.read();
        render_times[frame_idx] = render_end - frame_start;

        var srgb_band = band.toSrgb(srgb_buf) catch continue;

        const srgb_end = timer.read();
        srgb_times[frame_idx] = srgb_end - render_end;

        const grain = lib2.Grain{ .intensity = 0.4, .normalized_size = 0.01 };
        grain.apply(&srgb_band, viewport, scene.radius);

        const grain_end = timer.read();
        grain_times[frame_idx] = grain_end - srgb_end;
        frame_times[frame_idx] = grain_end - frame_start;
    }

    const total_ns = timer.read() - start_total;

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var sum_ns: u64 = 0;
    var render_sum: u64 = 0;
    var srgb_sum: u64 = 0;
    var grain_sum: u64 = 0;

    for (0..total_frames) |i| {
        const t = frame_times[i];
        min_ns = @min(min_ns, t);
        max_ns = @max(max_ns, t);
        sum_ns += t;
        render_sum += render_times[i];
        srgb_sum += srgb_times[i];
        grain_sum += grain_times[i];
    }

    const avg_ns = sum_ns / total_frames;
    const total_ms = @as(f64, @floatFromInt(total_ns)) / 1_000_000.0;
    const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;
    const min_ms = @as(f64, @floatFromInt(min_ns)) / 1_000_000.0;
    const max_ms = @as(f64, @floatFromInt(max_ns)) / 1_000_000.0;
    const fps = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));
    const render_ms = @as(f64, @floatFromInt(render_sum / total_frames)) / 1_000_000.0;
    const srgb_ms = @as(f64, @floatFromInt(srgb_sum / total_frames)) / 1_000_000.0;
    const grain_ms = @as(f64, @floatFromInt(grain_sum / total_frames)) / 1_000_000.0;

    std.debug.print("\n=== lib2 Performance Results ===\n", .{});
    std.debug.print("Resolution: {d}x{d}\n", .{ width, height });
    std.debug.print("Frames: {d}\n", .{total_frames});
    std.debug.print("Total time: {d:.2} ms\n", .{total_ms});
    std.debug.print("Average: {d:.3} ms/frame ({d:.1} FPS)\n", .{ avg_ms, fps });
    std.debug.print("Min: {d:.3} ms\n", .{min_ms});
    std.debug.print("Max: {d:.3} ms\n", .{max_ms});
    std.debug.print("\n--- Breakdown (avg per frame) ---\n", .{});
    std.debug.print("Render: {d:.3} ms\n", .{render_ms});
    std.debug.print("sRGB:   {d:.3} ms\n", .{srgb_ms});
    std.debug.print("Grain:  {d:.3} ms\n", .{grain_ms});
}
