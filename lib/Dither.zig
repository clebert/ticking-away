const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Oklab = @import("Oklab.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

normalized_strength: f32,
normalized_chroma_emphasis: f32,
palette: Palette,

const channels = 3;

pub fn errorBufferSize(width: usize) usize {
    return width * channels * 2;
}

pub fn apply(
    self: Self,
    band: Image.Band(Linear),
    srgb_buffer: []Srgb,
    error_buffer: []f32,
) !Image.Band(Srgb) {
    const width = band.width;
    const height = band.bandHeight();

    if (srgb_buffer.len != band.buffer.len) return error.BufferSizeMismatch;

    const stride = width * channels;

    std.debug.assert(error_buffer.len >= stride * 2);
    std.debug.assert(self.normalized_strength >= 0.0 and self.normalized_strength <= 1.0);

    std.debug.assert(
        self.normalized_chroma_emphasis >= 0.0 and self.normalized_chroma_emphasis <= 1.0,
    );

    // Zero the entire buffer for the first band of each frame.
    // Subsequent bands carry forward pending errors in slot 0.
    if (band.y_offset == 0) {
        @memset(error_buffer[0 .. stride * 2], 0);
    }

    // Between bands, apply() maintains the invariant: pending errors in
    // slot 0, slot 1 zeroed. Assert slot 1 is clean as a partial check.
    std.debug.assert(std.mem.allEqual(f32, error_buffer[stride..][0..stride], 0));

    const chroma_weight = self.normalized_chroma_emphasis * 2.0;
    const lightness_weight = (1.0 - self.normalized_chroma_emphasis) * 2.0;

    var current_row: usize = 0;

    for (0..height) |y| {
        const serpentine = (band.imageY(y) % 2) == 1;
        const current = error_buffer[current_row * stride ..][0..stride];
        const next = error_buffer[(1 - current_row) * stride ..][0..stride];

        for (0..width) |iteration| {
            const x = if (serpentine) width - 1 - iteration else iteration;
            const step: i32 = if (serpentine) -1 else 1;

            const linear = band.colorAt(x, y).*;
            const alpha: u8 = @intFromFloat(@round(std.math.clamp(linear.vec[3], 0.0, 1.0) * 255.0));
            const error_offset = x * channels;

            // Background pixels (never rendered to): output palette black directly
            // without error diffusion to prevent color bleeding at circle boundary
            if (linear.vec[0] == 0 and linear.vec[1] == 0 and linear.vec[2] == 0) {
                srgb_buffer[y * width + x] = .{
                    .r = self.palette.srgb_colors[0].r,
                    .g = self.palette.srgb_colors[0].g,
                    .b = self.palette.srgb_colors[0].b,
                    .a = alpha,
                };

                continue;
            }

            const oklab = linear.toOklab();
            const adjusted_l = std.math.clamp(oklab.vec[0] + current[error_offset], 0.0, 1.0);
            const adjusted_a = oklab.vec[1] + current[error_offset + 1];
            const adjusted_b = oklab.vec[2] + current[error_offset + 2];

            const index = findClosest(self.palette.oklab_colors, adjusted_l, adjusted_a, adjusted_b, lightness_weight, chroma_weight);

            const quantized = self.palette.oklab_colors[index];

            const err = [channels]f32{
                (adjusted_l - quantized.vec[0]) * self.normalized_strength,
                (adjusted_a - quantized.vec[1]) * self.normalized_strength,
                (adjusted_b - quantized.vec[2]) * self.normalized_strength,
            };

            srgb_buffer[y * width + x] = .{
                .r = self.palette.srgb_colors[index].r,
                .g = self.palette.srgb_colors[index].g,
                .b = self.palette.srgb_colors[index].b,
                .a = alpha,
            };

            const signed_x: i32 = @intCast(x);
            const signed_width: i32 = @intCast(width);
            const forward = signed_x + step;
            const back = signed_x - step;

            if (forward >= 0 and forward < signed_width) {
                const forward_offset = @as(usize, @intCast(forward)) * channels;

                inline for (0..channels) |c| {
                    current[forward_offset + c] += err[c] * (7.0 / 16.0);
                    next[forward_offset + c] += err[c] * (1.0 / 16.0);
                }
            }

            if (back >= 0 and back < signed_width) {
                const back_offset = @as(usize, @intCast(back)) * channels;

                inline for (0..channels) |c| {
                    next[back_offset + c] += err[c] * (3.0 / 16.0);
                }
            }

            inline for (0..channels) |c| {
                next[error_offset + c] += err[c] * (5.0 / 16.0);
            }
        }

        @memset(current, 0);

        current_row = 1 - current_row;
    }

    // Ensure pending errors are in slot 0 for the next band call.
    // After odd-height bands, pending errors end up in slot 1.
    if (current_row != 0) {
        @memcpy(error_buffer[0..stride], error_buffer[stride..][0..stride]);
        @memset(error_buffer[stride..][0..stride], 0);
    }

    return .{ .buffer = srgb_buffer, .width = width, .y_offset = band.y_offset };
}

fn findClosest(
    palette: [Palette.color_count]Oklab,
    l: f32,
    a: f32,
    b: f32,
    lightness_weight: f32,
    chroma_weight: f32,
) usize {
    var best_index: usize = 0;
    var best_distance: f32 = std.math.floatMax(f32);

    for (palette, 0..) |color, i| {
        // Weighted Oklab distance: (2/cw)*dL² + cw*(da²+db²)
        const delta_l = l - color.vec[0];
        const delta_a = a - color.vec[1];
        const delta_b = b - color.vec[2];

        const distance = lightness_weight * delta_l * delta_l +
            chroma_weight * (delta_a * delta_a + delta_b * delta_b);

        if (distance < best_distance) {
            best_distance = distance;
            best_index = i;
        }
    }

    return best_index;
}

pub const Palette = struct {
    pub const color_count = 6;

    oklab_colors: [color_count]Oklab,
    srgb_colors: [color_count]Srgb,

    fn fromSrgb(comptime srgb_colors: [color_count]Srgb) Palette {
        @setEvalBranchQuota(10_000);

        var oklab_colors: [color_count]Oklab = undefined;

        for (srgb_colors, 0..) |srgb, i| {
            oklab_colors[i] = srgb.toLinear().toOklab();
        }

        return .{ .oklab_colors = oklab_colors, .srgb_colors = srgb_colors };
    }
};

const ideal_palette = Palette.fromSrgb(.{
    .{ .r = 0, .g = 0, .b = 0 },
    .{ .r = 255, .g = 255, .b = 255 },
    .{ .r = 255, .g = 255, .b = 0 },
    .{ .r = 255, .g = 0, .b = 0 },
    .{ .r = 0, .g = 0, .b = 255 },
    .{ .r = 0, .g = 255, .b = 0 },
});

const spectra6_inky_palette = Palette.fromSrgb(.{
    .{ .r = 0, .g = 0, .b = 0 },
    .{ .r = 161, .g = 164, .b = 165 },
    .{ .r = 208, .g = 190, .b = 71 },
    .{ .r = 156, .g = 72, .b = 75 },
    .{ .r = 61, .g = 59, .b = 94 },
    .{ .r = 58, .g = 91, .b = 70 },
});

const spectra6_epdopt_palette = Palette.fromSrgb(.{
    .{ .r = 25, .g = 30, .b = 33 },
    .{ .r = 232, .g = 232, .b = 232 },
    .{ .r = 239, .g = 222, .b = 68 },
    .{ .r = 178, .g = 19, .b = 24 },
    .{ .r = 33, .g = 87, .b = 186 },
    .{ .r = 18, .g = 95, .b = 32 },
});

const spectra6_trmnl_palette = Palette.fromSrgb(.{
    .{ .r = 0, .g = 0, .b = 0 },
    .{ .r = 192, .g = 192, .b = 192 },
    .{ .r = 192, .g = 192, .b = 0 },
    .{ .r = 192, .g = 0, .b = 0 },
    .{ .r = 0, .g = 0, .b = 192 },
    .{ .r = 0, .g = 192, .b = 0 },
});

pub const PaletteId = enum {
    ideal,
    spectra6_inky,
    spectra6_epdopt,
    spectra6_trmnl,

    pub fn palette(self: PaletteId) Palette {
        return switch (self) {
            .ideal => ideal_palette,
            .spectra6_inky => spectra6_inky_palette,
            .spectra6_epdopt => spectra6_epdopt_palette,
            .spectra6_trmnl => spectra6_trmnl_palette,
        };
    }
};

test "apply produces only palette colors" {
    const image = Image.init(4, 4);

    var linear_buffer = [_]Linear{Linear.init(0.5, 0.2, 0.1, 1.0)} ** 16;
    var srgb_buffer: [16]Srgb = undefined;
    var error_buffer: [4 * channels * 2]f32 = undefined;

    const linear_band = image.band(Linear, &linear_buffer, 4, 0) catch unreachable;

    const dither = Self{
        .normalized_strength = 1.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    const srgb_band = dither.apply(linear_band, &srgb_buffer, &error_buffer) catch unreachable;

    for (srgb_band.buffer) |pixel| {
        var found = false;

        for (dither.palette.srgb_colors) |palette_color| {
            if (pixel.r == palette_color.r and
                pixel.g == palette_color.g and
                pixel.b == palette_color.b)
            {
                found = true;
                break;
            }
        }

        try std.testing.expect(found);
    }
}

test "apply preserves alpha channel" {
    const image = Image.init(2, 2);

    var linear_buffer = [_]Linear{Linear.init(0.5, 0.5, 0.5, 0.75)} ** 4;
    var srgb_buffer: [4]Srgb = undefined;
    var error_buffer: [2 * channels * 2]f32 = undefined;

    const linear_band = image.band(Linear, &linear_buffer, 2, 0) catch unreachable;

    const dither = Self{
        .normalized_strength = 1.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    const srgb_band = dither.apply(linear_band, &srgb_buffer, &error_buffer) catch unreachable;

    for (srgb_band.buffer) |pixel| {
        try std.testing.expectEqual(@as(u8, 191), pixel.a);
    }
}

test "apply with zero strength still quantizes to palette" {
    const image = Image.init(4, 4);

    var linear_buffer = [_]Linear{Linear.init(0.3, 0.6, 0.1, 1.0)} ** 16;
    var srgb_buffer: [16]Srgb = undefined;
    var error_buffer: [4 * channels * 2]f32 = undefined;

    const linear_band = image.band(Linear, &linear_buffer, 4, 0) catch unreachable;

    const dither = Self{
        .normalized_strength = 0.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    const srgb_band = dither.apply(linear_band, &srgb_buffer, &error_buffer) catch unreachable;

    for (srgb_band.buffer) |pixel| {
        var found = false;

        for (dither.palette.srgb_colors) |palette_color| {
            if (pixel.r == palette_color.r and
                pixel.g == palette_color.g and
                pixel.b == palette_color.b)
            {
                found = true;
                break;
            }
        }

        try std.testing.expect(found);
    }
}

test "apply outputs palette black for background pixels without color bleeding" {
    const image = Image.init(4, 2);

    // Row of bright red pixels followed by row of black (background) pixels
    var linear_buffer: [8]Linear = undefined;

    for (0..4) |i| {
        linear_buffer[i] = Linear.init(1.0, 0.0, 0.0, 1.0);
    }

    for (4..8) |i| {
        linear_buffer[i] = Linear.init(0.0, 0.0, 0.0, 1.0);
    }

    var srgb_buffer: [8]Srgb = undefined;
    var error_buffer: [4 * channels * 2]f32 = undefined;

    const linear_band = image.band(Linear, &linear_buffer, 2, 0) catch unreachable;

    const dither = Self{
        .normalized_strength = 1.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    const srgb_band = dither.apply(linear_band, &srgb_buffer, &error_buffer) catch unreachable;

    // Background pixels must be exactly palette black with no color bleeding
    const palette_black = dither.palette.srgb_colors[0];

    for (4..8) |i| {
        const pixel = srgb_band.buffer[i];

        try std.testing.expectEqual(palette_black.r, pixel.r);
        try std.testing.expectEqual(palette_black.g, pixel.g);
        try std.testing.expectEqual(palette_black.b, pixel.b);
        try std.testing.expectEqual(@as(u8, 255), pixel.a);
    }
}

test "all palettes have black as first color" {
    const palette_ids = std.enums.values(PaletteId);

    for (palette_ids) |id| {
        const palette = id.palette();
        const first = palette.srgb_colors[0];

        // First color must be dark: all RGB channels <= 35
        try std.testing.expect(first.r <= 35);
        try std.testing.expect(first.g <= 35);
        try std.testing.expect(first.b <= 35);
    }
}

test "findClosest returns black for dark colors" {
    const palette = PaletteId.ideal.palette();
    const black_oklab = (Srgb{ .r = 10, .g = 10, .b = 10 }).toLinear().toOklab();

    const index = findClosest(
        palette.oklab_colors,
        black_oklab.vec[0],
        black_oklab.vec[1],
        black_oklab.vec[2],
        1.0,
        2.0,
    );

    try std.testing.expectEqual(@as(usize, 0), index);
}

test "error diffusion propagates to subsequent rows" {
    const width = 8;
    const height = 4;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    // Mid-gray: falls between black and white palette entries, generating error every pixel
    var linear_buffer = [_]Linear{Linear.init(0.2, 0.2, 0.2, 1.0)} ** pixel_count;

    const dither = Self{
        .normalized_strength = 1.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    // With error diffusion (strength=1): errors propagate row-to-row
    var srgb_diffused: [pixel_count]Srgb = undefined;
    var error_buffer: [width * channels * 2]f32 = undefined;

    const linear_band = image.band(Linear, &linear_buffer, height, 0) catch unreachable;

    _ = dither.apply(linear_band, &srgb_diffused, &error_buffer) catch unreachable;

    // Without error diffusion (strength=0): each pixel quantized independently
    const no_diffusion = Self{
        .normalized_strength = 0.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    var srgb_independent: [pixel_count]Srgb = undefined;

    _ = no_diffusion.apply(linear_band, &srgb_independent, &error_buffer) catch unreachable;

    // With strength=0, all pixels map to the same nearest color (no variation).
    // With strength=1, error diffusion should cause at least some pixels to differ.
    var differs = false;

    for (&srgb_diffused, &srgb_independent) |d, i| {
        if (d.r != i.r or d.g != i.g or d.b != i.b) {
            differs = true;
            break;
        }
    }

    try std.testing.expect(differs);
}

test "multi-band dithering matches single-band dithering" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    // Vertical gradient: varies per row so error diffusion is meaningful across bands
    var linear_buffer: [pixel_count]Linear = undefined;

    for (0..height) |y| {
        const t: f32 = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));

        for (0..width) |x| {
            linear_buffer[y * width + x] = Linear.init(t * 0.8, t * 0.3, (1.0 - t) * 0.5, 1.0);
        }
    }

    const dither = Self{
        .normalized_strength = 1.0,
        .normalized_chroma_emphasis = 0.667,
        .palette = PaletteId.ideal.palette(),
    };

    // Reference: single-band (full height)
    var reference: [pixel_count]Srgb = undefined;
    var error_buffer: [width * channels * 2]f32 = undefined;

    const full_band = image.band(Linear, &linear_buffer, height, 0) catch unreachable;

    _ = dither.apply(full_band, &reference, &error_buffer) catch unreachable;

    // Test with band heights: 1 (extreme), 2 (even), 3 (odd), 4 (even), 8, 16
    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output: [pixel_count]Srgb = undefined;
        var band_srgb_buffer: [pixel_count]Srgb = undefined;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;
            const band_linear = linear_buffer[row_start..][0..band_pixels];

            const narrow_band = image.band(Linear, band_linear, band_height, band_index) catch unreachable;

            const srgb_band = dither.apply(
                narrow_band,
                band_srgb_buffer[0..band_pixels],
                &error_buffer,
            ) catch unreachable;

            @memcpy(banded_output[row_start..][0..band_pixels], srgb_band.buffer);
        }

        for (&reference, &banded_output, 0..) |ref, actual, i| {
            const y = i / width;
            const x = i % width;

            std.testing.expectEqual(ref.r, actual.r) catch {
                std.debug.print("band_height={d}: mismatch at ({d},{d}) r: expected {d}, got {d}\n", .{ band_height, x, y, ref.r, actual.r });
                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.g, actual.g) catch {
                std.debug.print("band_height={d}: mismatch at ({d},{d}) g: expected {d}, got {d}\n", .{ band_height, x, y, ref.g, actual.g });
                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.b, actual.b) catch {
                std.debug.print("band_height={d}: mismatch at ({d},{d}) b: expected {d}, got {d}\n", .{ band_height, x, y, ref.b, actual.b });
                return error.TestUnexpectedResult;
            };
        }
    }
}
