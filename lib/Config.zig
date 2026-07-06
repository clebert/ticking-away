const std = @import("std");

const Rainbow = @import("Rainbow.zig");

const Self = @This();

pub const Texture = enum { none, grain, dither_pebble, dither_trmnl };

background_enabled: bool,
prism_normalized_size: f32,
prism_glow_normalized_width: f32,
rainbow_normalized_spread: f32,
rainbow_style: Rainbow.Style,
hand_glow_normalized_width: f32,
texture: Texture,
grain_normalized_deviation: f32,

const json_source = @embedFile("config.json");

/// The shared baseline every target renders from, parsed from `config.json` at
/// comptime and range-checked at compile time: it costs nothing at runtime and a
/// malformed or out-of-range `config.json` fails the build. Native targets copy this
/// and override only the fields they change; the browser instead feeds live JSON
/// through `parse`.
pub const default: Self = value: {
    @setEvalBranchQuota(100_000);

    // The scanner allocates a small object-nesting bit-stack into `buffer`, so it must
    // be big enough; `json_source.len` is a safe over-estimate. This evaluates at
    // comptime only because that allocation is align-1, which skips the pointer-align
    // math (`@intFromPtr`) that isn't comptime-legal — the reason the arena-allocating
    // `parseFromSlice` can't run here and `parseFromSliceLeaky` can.
    var buffer: [json_source.len]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buffer);

    const config = std.json.parseFromSliceLeaky(Self, fixed_buffer.allocator(), json_source, .{}) catch |err|
        @compileError("config.json failed to parse: " ++ @errorName(err));

    validateRanges(config) catch |err|
        @compileError("config.json is out of range: " ++ @errorName(err));

    break :value config;
};

/// Returns a copy of `self` with the fields named in `overrides` replaced, so a
/// target restates only what it changes from `default`. An unknown field name in
/// `overrides` fails to compile.
pub fn with(self: Self, overrides: anytype) Self {
    var config = self;

    inline for (@typeInfo(@TypeOf(overrides)).@"struct".fields) |field| {
        @field(config, field.name) = @field(overrides, field.name);
    }

    return config;
}

/// Safe to return `parsed.value` after `deinit` because `Self` contains only
/// value types (f32, bool, enums) — no heap-allocated fields that reference
/// the parsed arena.
pub fn parse(allocator: std.mem.Allocator, json_text: []const u8) !Self {
    const parsed = try std.json.parseFromSlice(Self, allocator, json_text, .{});

    defer parsed.deinit();

    try validateRanges(parsed.value);

    return parsed.value;
}

fn validateRanges(config: Self) !void {
    inline for (@typeInfo(Self).@"struct".fields) |field| {
        if (field.type == f32) {
            const value = @field(config, field.name);

            if (value < 0.0 or value > 1.0) return error.OutOfRange;
        }
    }

    // Prism.init requires a strictly positive size.
    if (config.prism_normalized_size <= 0.0) return error.OutOfRange;
}

test "with replaces only the named fields" {
    const config = default.with(.{ .background_enabled = false, .texture = .dither_trmnl });

    try std.testing.expectEqual(false, config.background_enabled);
    try std.testing.expectEqual(Texture.dither_trmnl, config.texture);
    try std.testing.expectEqual(default.prism_normalized_size, config.prism_normalized_size);
    try std.testing.expectEqual(default.prism_glow_normalized_width, config.prism_glow_normalized_width);
}

test "validateRanges rejects zero-size prism" {
    var config = default;

    config.prism_normalized_size = 0.0;

    try std.testing.expectError(error.OutOfRange, validateRanges(config));
}
