const std = @import("std");

const Rainbow = @import("Rainbow.zig");

const Self = @This();

pub const Texture = enum { none, grain, dither_pebble, dither_trmnl };

background_enabled: bool,
prism_normalized_size: f32,
prism_glow_linear_green: f32,
prism_glow_normalized_width: f32,
rainbow_normalized_spread: f32,
hand_glow_normalized_width: f32,
rainbow_palette_id: Rainbow.PaletteId,
texture: Texture,
grain_normalized_deviation: f32,
supersample_enabled: bool,

const json_source = @embedFile("config.json");

pub fn init(allocator: std.mem.Allocator) !Self {
    return parse(allocator, json_source);
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

test "init returns valid config from defaults" {
    _ = try init(std.testing.allocator);
}

test "validateRanges rejects zero-size prism" {
    var config = try init(std.testing.allocator);

    config.prism_normalized_size = 0.0;

    try std.testing.expectError(error.OutOfRange, validateRanges(config));
}
