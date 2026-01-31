// zig build perf-zig -Doptimize=ReleaseFast
// ./zig-out/bin/perf-zig 10

const std = @import("std");

const lib = @import("lib");

const width: usize = 5120;
const height: usize = 5120;
const max_frames: usize = 720;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Parse frame count argument
    var args = std.process.args();
    _ = args.skip(); // skip program name

    const total_frames: usize = if (args.next()) |arg|
        std.fmt.parseInt(usize, arg, 10) catch {
            std.debug.print("Usage: perf-zig [frames]\n", .{});
            std.debug.print("  frames: number of frames to render (1-720, default: 720)\n", .{});
            return;
        }
    else
        max_frames;

    if (total_frames == 0 or total_frames > max_frames) {
        std.debug.print("Error: frames must be between 1 and {d}\n", .{max_frames});
        return;
    }

    // Pre-allocate buffers
    std.debug.print("Allocating buffers for {d}x{d} resolution...\n", .{ width, height });

    const pixel_count = width * height;
    const linear_colors = try allocator.alloc(lib.color_space.Linear, pixel_count);
    defer allocator.free(linear_colors);

    const srgba_colors = try allocator.alloc(lib.color_space.Srgba, pixel_count);
    defer allocator.free(srgba_colors);

    const frame_times = try allocator.alloc(u64, total_frames);
    defer allocator.free(frame_times);

    // Initialize scene with default config
    var scene = lib.watchface.Scene.init(width, height);

    // Timing
    std.debug.print("Running benchmark: {d} frames...\n", .{total_frames});

    var timer = try std.time.Timer.start();
    const start_total = timer.read();

    for (0..total_frames) |frame_idx| {
        const hour = frame_idx / 60;
        const minute = frame_idx % 60;

        const frame_start = timer.read();

        scene.setTime(@intCast(hour), @floatFromInt(minute));
        var band = lib.frame.Band{
            .linear_colors = linear_colors,
            .srgba_colors = srgba_colors,
            .width = width,
            .height = height,
            .y_offset = 0,
            .total_height = height,
        };
        scene.render(&band);

        frame_times[frame_idx] = timer.read() - frame_start;
    }

    const total_ns = timer.read() - start_total;

    // Compute statistics
    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var sum_ns: u64 = 0;

    for (frame_times) |t| {
        min_ns = @min(min_ns, t);
        max_ns = @max(max_ns, t);
        sum_ns += t;
    }

    const avg_ns = sum_ns / total_frames;
    const total_ms = @as(f64, @floatFromInt(total_ns)) / 1_000_000.0;
    const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;
    const min_ms = @as(f64, @floatFromInt(min_ns)) / 1_000_000.0;
    const max_ms = @as(f64, @floatFromInt(max_ns)) / 1_000_000.0;
    const fps = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

    // Print results
    std.debug.print("\n=== Performance Results ===\n", .{});
    std.debug.print("Resolution: {d}x{d}\n", .{ width, height });
    std.debug.print("Frames: {d}\n", .{total_frames});
    std.debug.print("Total time: {d:.2} ms\n", .{total_ms});
    std.debug.print("Average: {d:.3} ms/frame ({d:.1} FPS)\n", .{ avg_ms, fps });
    std.debug.print("Min: {d:.3} ms\n", .{min_ms});
    std.debug.print("Max: {d:.3} ms\n", .{max_ms});
}
