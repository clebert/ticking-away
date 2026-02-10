const std = @import("std");

const Dither = @import("Dither.zig");
const Glow = @import("Glow.zig");
const Rainbow = @import("Rainbow.zig");

const Self = @This();

background_enabled: bool,
prism_normalized_size: f32,
prism_glow_linear_green: f32,
prism_glow_normalized_width: f32,
prism_glow_falloff: Glow.Falloff,
rainbow_normalized_spread: f32,
hand_glow_normalized_width: f32,
hand_glow_falloff: Glow.Falloff,
rainbow_palette_id: Rainbow.PaletteId,
grain_enabled: bool,
grain_normalized_deviation: f32,
dither_enabled: bool,
dither_palette_id: Dither.PaletteId,
dither_normalized_strength: f32,
dither_normalized_chroma_emphasis: f32,

const json_source = @embedFile("config.json");

pub fn init(allocator: std.mem.Allocator) !Self {
    return parse(allocator, json_source);
}

/// Safe to return `parsed.value` after `deinit` because `Self` contains only
/// value types (f32, bool, enums) — no heap-allocated fields that reference
/// the parsed arena. Adding a slice or pointer field would require rethinking.
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
}

test "init returns valid config from defaults" {
    _ = try init(std.testing.allocator);
}
