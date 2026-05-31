//! Generates a void-and-cluster blue-noise threshold tile and writes it as a raw `u8`
//! file — one byte per pixel (the dither threshold, row-major), which `lib/dither.zig`
//! embeds via @embedFile. Run from the repo root: `zig run tools/blue_noise_generator.zig`.
//!
//! Void-and-cluster (Ulichney 1993): rank every pixel so that, at any threshold, the
//! "on" pixels form a homogeneous blue-noise pattern. The Gaussian energy field is
//! maintained incrementally and the per-step global min/max is accelerated with a
//! per-row min/max index, so generating even a 512×512 tile stays a few seconds.

const std = @import("std");

// The committed tile is 64×64 at lib/blue_noise.bin (run from the repo root). lib/dither.zig
// derives its tile size from the embedded file, so retiling is just editing `size` here.
const size: usize = 64;
const output_path = "lib/blue_noise.bin";

const sigma = 1.9;
const radius = 4;
const ones_fraction = 10;
const seed = 0x9E3779B97F4A7C15;

const Grid = struct {
    energy: []f32,
    pattern: []u8, // 0 = unset, 1 = set
    row_min_value: []f32,
    row_min_index: []usize,
    row_max_value: []f32,
    row_max_index: []usize,
    kernel: []const Tap,

    const Tap = struct { dy: i32, dx: i32, weight: f32 };

    const kernel_length = (2 * radius + 1) * (2 * radius + 1);

    fn init(allocator: std.mem.Allocator) !Grid {
        const count = size * size;

        const taps = try allocator.alloc(Tap, kernel_length);

        var tap_index: usize = 0;
        var dy: i32 = -radius;

        while (dy <= radius) : (dy += 1) {
            var dx: i32 = -radius;

            while (dx <= radius) : (dx += 1) {
                const squared: f32 = @floatFromInt(dx * dx + dy * dy);

                taps[tap_index] = .{
                    .dy = dy,
                    .dx = dx,
                    .weight = @exp(-squared / (2.0 * sigma * sigma)),
                };

                tap_index += 1;
            }
        }

        const grid = Grid{
            .energy = try allocator.alloc(f32, count),
            .pattern = try allocator.alloc(u8, count),
            .row_min_value = try allocator.alloc(f32, size),
            .row_min_index = try allocator.alloc(usize, size),
            .row_max_value = try allocator.alloc(f32, size),
            .row_max_index = try allocator.alloc(usize, size),
            .kernel = taps,
        };

        @memset(grid.energy, 0);
        @memset(grid.pattern, 0);

        // Seed the per-row min/max caches so largestVoid/tightestCluster are well-defined
        // before the first set/clear, independent of how placement happens to cover rows.
        grid.rebuildAll();

        return grid;
    }

    fn wrap(value: i32) usize {
        const signed_size: i32 = @intCast(size);
        return @intCast(@mod(value, signed_size));
    }

    /// Adds (sign = +1) or removes (sign = -1) a point's Gaussian contribution.
    fn bump(self: Grid, index: usize, sign: f32) void {
        const center_y: i32 = @intCast(index / size);
        const center_x: i32 = @intCast(index % size);

        for (self.kernel) |tap| {
            const y = wrap(center_y + tap.dy);
            const x = wrap(center_x + tap.dx);

            self.energy[y * size + x] += sign * tap.weight;
        }
    }

    fn rebuildRow(self: Grid, row: usize) void {
        var min_value: f32 = std.math.inf(f32);
        var min_index: usize = row * size;
        var max_value: f32 = -std.math.inf(f32);
        var max_index: usize = row * size;

        for (0..size) |column| {
            const index = row * size + column;
            const value = self.energy[index];

            if (self.pattern[index] == 0 and value < min_value) {
                min_value = value;
                min_index = index;
            }

            if (self.pattern[index] == 1 and value > max_value) {
                max_value = value;
                max_index = index;
            }
        }

        self.row_min_value[row] = min_value;
        self.row_min_index[row] = min_index;
        self.row_max_value[row] = max_value;
        self.row_max_index[row] = max_index;
    }

    fn rebuildAll(self: Grid) void {
        for (0..size) |row| self.rebuildRow(row);
    }

    /// Rebuilds every row the last bump at `index` could have touched.
    fn rebuildAround(self: Grid, index: usize) void {
        const center_y: i32 = @intCast(index / size);
        var offset: i32 = -radius;

        while (offset <= radius) : (offset += 1) {
            self.rebuildRow(wrap(center_y + offset));
        }
    }

    fn largestVoid(self: Grid) usize {
        var best_value: f32 = std.math.inf(f32);
        var best_index: usize = 0;

        for (0..size) |row| {
            if (self.row_min_value[row] < best_value) {
                best_value = self.row_min_value[row];
                best_index = self.row_min_index[row];
            }
        }

        // A non-finite best means the grid had no void at all; callers never ask for one when the
        // grid is full, so fail loudly rather than return the bogus default index 0.
        std.debug.assert(std.math.isFinite(best_value));

        return best_index;
    }

    fn tightestCluster(self: Grid) usize {
        var best_value: f32 = -std.math.inf(f32);
        var best_index: usize = 0;

        for (0..size) |row| {
            if (self.row_max_value[row] > best_value) {
                best_value = self.row_max_value[row];
                best_index = self.row_max_index[row];
            }
        }

        // A non-finite best means the grid had no cluster at all; callers never ask for one when
        // the grid is empty, so fail loudly rather than return the bogus default index 0.
        std.debug.assert(std.math.isFinite(best_value));

        return best_index;
    }

    fn set(self: Grid, index: usize) void {
        self.pattern[index] = 1;
        self.bump(index, 1.0);
        self.rebuildAround(index);
    }

    fn clear(self: Grid, index: usize) void {
        self.pattern[index] = 0;
        self.bump(index, -1.0);
        self.rebuildAround(index);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const count = size * size;

    var grid = try Grid.init(allocator);

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const ones = count / ones_fraction;
    var placed: usize = 0;

    while (placed < ones) {
        const index = random.uintLessThan(usize, count);

        if (grid.pattern[index] == 0) {
            grid.set(index);
            placed += 1;
        }
    }

    // Redistribute the initial random points into a homogeneous prototype pattern.
    var iteration: usize = 0;

    while (iteration < count) : (iteration += 1) {
        const cluster = grid.tightestCluster();
        grid.clear(cluster);

        const void_index = grid.largestVoid();
        grid.set(void_index);

        if (void_index == cluster) break;
    }

    const prototype_pattern = try allocator.dupe(u8, grid.pattern);
    const prototype_energy = try allocator.dupe(f32, grid.energy);

    const rank = try allocator.alloc(u32, count);

    // Phase 1: rank the prototype's points from `ones - 1` down to 0 by repeatedly
    // removing the tightest cluster.
    {
        var phase_rank: usize = ones;

        while (phase_rank > 0) {
            phase_rank -= 1;

            const cluster = grid.tightestCluster();
            rank[cluster] = @intCast(phase_rank);
            grid.clear(cluster);
        }
    }

    // Phase 2/3: from the prototype, rank the rest from `ones` up to `count - 1` by
    // repeatedly filling the largest void.
    @memcpy(grid.pattern, prototype_pattern);
    @memcpy(grid.energy, prototype_energy);
    grid.rebuildAll();

    {
        var phase_rank: usize = ones;

        while (phase_rank < count) : (phase_rank += 1) {
            const void_index = grid.largestVoid();
            rank[void_index] = @intCast(phase_rank);
            grid.set(void_index);
        }
    }

    const bytes = try allocator.alloc(u8, count);
    const scale: f32 = @floatFromInt(count);

    for (0..count) |i| {
        const threshold = (@as(f32, @floatFromInt(rank[i])) + 0.5) / scale;
        bytes[i] = @intFromFloat(@min(255.0, @floor(threshold * 256.0)));
    }

    const file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var buffered = file.writer(io, &buffer);
    const out = &buffered.interface;

    try out.writeAll(bytes);
    try out.flush();
}
