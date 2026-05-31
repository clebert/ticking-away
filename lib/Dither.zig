const std = @import("std");

const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Oklab = @import("Oklab.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

palette: Palette,

const channels = 3;

// Oklab a/b above which a colour (or pixel) counts as warm; see shadowWarmLimit.
const warm_chroma = 0.03;
// Lightness below which a cool pixel drops warm cube colours from its search.
const shadow_lightness = 0.5;

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

    // Zero the entire buffer for the first band of each frame.
    // Subsequent bands carry forward pending errors in slot 0.
    if (band.y_offset == 0) {
        @memset(error_buffer[0 .. stride * 2], 0);
    }

    // Between bands, apply() maintains the invariant: pending errors in
    // slot 0, slot 1 zeroed. Assert slot 1 is clean as a partial check.
    std.debug.assert(std.mem.allEqual(f32, error_buffer[stride..][0..stride], 0));

    var current_row: usize = 0;

    for (0..height) |y| {
        const serpentine = (band.imageY(y) % 2) == 1;
        const current = error_buffer[current_row * stride ..][0..stride];
        const next = error_buffer[(1 - current_row) * stride ..][0..stride];

        for (0..width) |iteration| {
            const x = if (serpentine) width - 1 - iteration else iteration;
            const step: i32 = if (serpentine) -1 else 1;

            const linear = band.colorAt(x, y).*;
            const alpha: u8 = Srgb.clampedByte(linear.vec[3] * 255.0);
            const error_offset = x * channels;

            // Background pixels (never rendered to): output palette black directly
            // without error diffusion to prevent color bleeding at the circle boundary.
            if (linear.vec[0] == 0 and linear.vec[1] == 0 and linear.vec[2] == 0) {
                const black = self.palette.black();

                srgb_buffer[y * width + x] = .{
                    .r = black.r,
                    .g = black.g,
                    .b = black.b,
                    .a = alpha,
                };

                continue;
            }

            const oklab = linear.toOklab();
            const adjusted_l = std.math.clamp(oklab.vec[0] + current[error_offset], 0.0, 1.0);
            const adjusted_a = oklab.vec[1] + current[error_offset + 1];
            const adjusted_b = oklab.vec[2] + current[error_offset + 2];

            const index = findClosest(
                self.palette.oklab_colors,
                adjusted_l,
                adjusted_a,
                adjusted_b,
                shadowWarmLimit(oklab),
            );

            const quantized = self.palette.oklab_colors[index];

            const quantization_error = [channels]f32{
                adjusted_l - quantized.vec[0],
                adjusted_a - quantized.vec[1],
                adjusted_b - quantized.vec[2],
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

                inline for (0..channels) |channel| {
                    current[forward_offset + channel] += quantization_error[channel] * (7.0 / 16.0);
                    next[forward_offset + channel] += quantization_error[channel] * (1.0 / 16.0);
                }
            }

            if (back >= 0 and back < signed_width) {
                const back_offset = @as(usize, @intCast(back)) * channels;

                inline for (0..channels) |channel| {
                    next[back_offset + channel] += quantization_error[channel] * (3.0 / 16.0);
                }
            }

            inline for (0..channels) |channel| {
                next[error_offset + channel] += quantization_error[channel] * (5.0 / 16.0);
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

/// The warm-chroma limit `findClosest` should use for a pixel of colour `oklab`.
///
/// The cube's darkest non-black tones are the saturated primaries — red sits at
/// Oklab L≈0.28 with no neutral dark counterpart — so error diffusion that nudges
/// a deep-shadow cool pixel toward neutral can let a primary win the nearest-colour
/// search once the accumulated error tilts its a/b that way, scattering a warm seam
/// through the prism glow's fade to black. For a cool pixel in shadow, return
/// `warm_chroma` so the search keeps only the cool/neutral corner of the cube
/// (a, b <= warm_chroma) — black, blues, cyans, the neutral grays and white — and
/// drops the reds (high a) along with the yellows and greens (both yellow-leaning,
/// high b). Bright or already-warm pixels (the rainbow) keep the full palette.
fn shadowWarmLimit(oklab: Oklab) f32 {
    const cool = oklab.vec[1] <= warm_chroma and oklab.vec[2] <= warm_chroma;

    return if (oklab.vec[0] < shadow_lightness and cool) warm_chroma else std.math.inf(f32);
}

/// Index of the nearest palette colour to `(l, a, b)` in Oklab, skipping colours
/// whose a or b exceeds `warm_limit` (pass `inf` to consider the whole palette).
fn findClosest(palette: []const Oklab, l: f32, a: f32, b: f32, warm_limit: f32) usize {
    var best_index: usize = 0;
    var best_distance: f32 = std.math.floatMax(f32);

    for (palette, 0..) |color, i| {
        if (color.vec[1] > warm_limit or color.vec[2] > warm_limit) continue;

        const delta_l = l - color.vec[0];
        const delta_a = a - color.vec[1];
        const delta_b = b - color.vec[2];
        const distance = delta_l * delta_l + delta_a * delta_a + delta_b * delta_b;

        if (distance < best_distance) {
            best_distance = distance;
            best_index = i;
        }
    }

    return best_index;
}

pub const Palette = struct {
    oklab_colors: []const Oklab,
    srgb_colors: []const Srgb,

    pub fn black(self: Palette) Srgb {
        return self.srgb_colors[0];
    }

    // The returned slices point at comptime-promoted static data, so the palette
    // outlives every caller. srgb_colors are stored verbatim; oklab_colors are
    // derived from them via the standard sRGB transfer function (srgb.toLinear).
    fn fromSrgb(comptime srgb_colors: []const Srgb) Palette {
        @setEvalBranchQuota(1_000_000);

        const oklab_colors = comptime blk: {
            var result: [srgb_colors.len]Oklab = undefined;

            for (srgb_colors, 0..) |srgb, i| {
                result[i] = srgb.toLinear().toOklab();
            }

            break :blk result;
        };

        return .{ .oklab_colors = &oklab_colors, .srgb_colors = srgb_colors };
    }
};

// The Pebble colour gamut: the 4x4x4 cube of {0, 85, 170, 255} per channel.
// Natural cube order places black at index 0, which black() and the background
// fast-path depend on.
pub const pebble64 = Palette.fromSrgb(&pebble64_srgb_colors);

const pebble64_srgb_colors = blk: {
    const levels = [_]u8{ 0, 85, 170, 255 };

    var colors: [64]Srgb = undefined;
    var index: usize = 0;

    for (levels) |r| {
        for (levels) |g| {
            for (levels) |b| {
                colors[index] = .{ .r = r, .g = g, .b = b };
                index += 1;
            }
        }
    }

    break :blk colors;
};

test "apply produces only palette colors" {
    const image = Image.init(4, 4);

    var linear_buffer = [_]Linear{Linear.init(0.5, 0.2, 0.1, 1.0)} ** 16;
    var srgb_buffer: [16]Srgb = undefined;
    var error_buffer: [errorBufferSize(4)]f32 = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 4, 0);
    const dither = Self{ .palette = pebble64 };
    const srgb_band = try dither.apply(linear_band, &srgb_buffer, &error_buffer);

    for (srgb_band.buffer) |pixel| {
        var found = false;

        for (pebble64.srgb_colors) |palette_color| {
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
    var error_buffer: [errorBufferSize(2)]f32 = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 2, 0);
    const dither = Self{ .palette = pebble64 };
    const srgb_band = try dither.apply(linear_band, &srgb_buffer, &error_buffer);

    for (srgb_band.buffer) |pixel| {
        try std.testing.expectEqual(@as(u8, 191), pixel.a);
    }
}

test "apply outputs palette black for background pixels without color bleeding" {
    const image = Image.init(4, 2);

    var linear_buffer: [8]Linear = undefined;

    for (0..4) |i| linear_buffer[i] = Linear.init(1.0, 0.0, 0.0, 1.0);
    for (4..8) |i| linear_buffer[i] = Linear.init(0.0, 0.0, 0.0, 1.0);

    var srgb_buffer: [8]Srgb = undefined;
    var error_buffer: [errorBufferSize(4)]f32 = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 2, 0);
    const dither = Self{ .palette = pebble64 };
    const srgb_band = try dither.apply(linear_band, &srgb_buffer, &error_buffer);

    const palette_black = pebble64.black();

    for (4..8) |i| {
        const pixel = srgb_band.buffer[i];

        try std.testing.expectEqual(palette_black.r, pixel.r);
        try std.testing.expectEqual(palette_black.g, pixel.g);
        try std.testing.expectEqual(palette_black.b, pixel.b);
        try std.testing.expectEqual(@as(u8, 255), pixel.a);
    }
}

test "findClosest returns black for dark colors" {
    const black_oklab = (Srgb{ .r = 10, .g = 10, .b = 10 }).toLinear().toOklab();

    const index = findClosest(
        pebble64.oklab_colors,
        black_oklab.vec[0],
        black_oklab.vec[1],
        black_oklab.vec[2],
        std.math.inf(f32),
    );

    try std.testing.expectEqual(@as(usize, 0), index);
}

test "findClosest skips colours above the warm limit" {
    // A near-neutral dark target whose closest cube colour is red (85,0,0); with
    // the warm limit it must instead pick a cool colour (red is excluded).
    const red = (Srgb{ .r = 85, .g = 0, .b = 0 }).toLinear().toOklab();

    const unrestricted = findClosest(
        pebble64.oklab_colors,
        red.vec[0],
        red.vec[1],
        red.vec[2],
        std.math.inf(f32),
    );
    const restricted = findClosest(pebble64.oklab_colors, red.vec[0], red.vec[1], red.vec[2], warm_chroma);

    try std.testing.expect(pebble64.oklab_colors[unrestricted].vec[1] > warm_chroma);
    try std.testing.expect(pebble64.oklab_colors[restricted].vec[1] <= warm_chroma);
    try std.testing.expect(pebble64.oklab_colors[restricted].vec[2] <= warm_chroma);
}

test "shadowWarmLimit restricts only cool pixels in shadow" {
    const dark_cyan = Linear.init(0.02, 0.06, 0.08, 1.0).toOklab();
    const bright_cyan = Linear.init(0.2, 0.6, 0.8, 1.0).toOklab();
    const dark_red = Linear.init(0.08, 0.0, 0.0, 1.0).toOklab();

    // Cool and in shadow: warm colours are excluded.
    try std.testing.expectEqual(warm_chroma, shadowWarmLimit(dark_cyan));
    // Bright cool, or dark warm: the whole palette stays available.
    try std.testing.expect(std.math.isInf(shadowWarmLimit(bright_cyan)));
    try std.testing.expect(std.math.isInf(shadowWarmLimit(dark_red)));
}

test "shadowWarmLimit boundary conditions pin its comparisons" {
    // Lightness is a strict `<`: a cool pixel exactly at shadow_lightness keeps the
    // full palette.
    try std.testing.expect(std.math.isInf(shadowWarmLimit(.{
        .vec = .{ shadow_lightness, 0.0, 0.0, 1.0 },
    })));

    // Chroma is a non-strict `<=`: a dark pixel with a or b exactly at warm_chroma
    // still counts as cool and is restricted.
    try std.testing.expectEqual(warm_chroma, shadowWarmLimit(.{
        .vec = .{ 0.3, warm_chroma, 0.0, 1.0 },
    }));
    try std.testing.expectEqual(warm_chroma, shadowWarmLimit(.{
        .vec = .{ 0.3, 0.0, warm_chroma, 1.0 },
    }));

    // Both chroma terms are checked: a dark pixel warm on either axis alone keeps
    // the full palette.
    try std.testing.expect(std.math.isInf(shadowWarmLimit(.{
        .vec = .{ 0.3, warm_chroma + 0.01, 0.0, 1.0 },
    })));
    try std.testing.expect(std.math.isInf(shadowWarmLimit(.{
        .vec = .{ 0.3, 0.0, warm_chroma + 0.01, 1.0 },
    })));
}

test "dithering a dark cyan field produces no warm pixels" {
    const width = 32;
    const height = 32;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    // A cyan glow fading to black, like the prism's inner glow. Baseline error
    // diffusion scatters warm specks here; shadowWarmLimit forbids them, so every
    // output stays cool in Oklab (a, b <= warm_chroma).
    var linear_buffer: [pixel_count]Linear = undefined;

    for (0..height) |y| {
        const t: f32 = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));

        for (0..width) |x| {
            linear_buffer[y * width + x] = Linear.init(0.01 * t, 0.075 * t, 0.1 * t, 1.0);
        }
    }

    var srgb_buffer: [pixel_count]Srgb = undefined;
    var error_buffer: [errorBufferSize(width)]f32 = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, height, 0);
    const dither = Self{ .palette = pebble64 };

    _ = try dither.apply(linear_band, &srgb_buffer, &error_buffer);

    var varies = false;

    for (srgb_buffer) |pixel| {
        const oklab = pixel.toLinear().toOklab();

        try std.testing.expect(oklab.vec[1] <= warm_chroma and oklab.vec[2] <= warm_chroma);

        if (pixel.r != srgb_buffer[0].r or
            pixel.g != srgb_buffer[0].g or
            pixel.b != srgb_buffer[0].b)
        {
            varies = true;
        }
    }

    // A uniform field (all black or all gray) would also satisfy the cool check,
    // so require the gradient to produce more than one palette colour.
    try std.testing.expect(varies);
}

test "error diffusion creates variation across a flat mid-tone" {
    const width = 8;
    const height = 4;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    // Mid-gray falls between cube levels, so diffusion must spread error and
    // mix at least two palette colours rather than producing a flat block.
    var linear_buffer = [_]Linear{Linear.init(0.2, 0.2, 0.2, 1.0)} ** pixel_count;
    var srgb_buffer: [pixel_count]Srgb = undefined;
    var error_buffer: [errorBufferSize(width)]f32 = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, height, 0);
    const dither = Self{ .palette = pebble64 };

    _ = try dither.apply(linear_band, &srgb_buffer, &error_buffer);

    var varies = false;

    for (srgb_buffer[1..]) |pixel| {
        if (pixel.r != srgb_buffer[0].r or pixel.g != srgb_buffer[0].g or pixel.b != srgb_buffer[0].b) {
            varies = true;
            break;
        }
    }

    try std.testing.expect(varies);
}

test "multi-band dithering matches single-band dithering" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const pixel_count = width * height;

    // Vertical gradient: varies per row so error diffusion is meaningful across bands.
    var linear_buffer: [pixel_count]Linear = undefined;

    for (0..height) |y| {
        const t: f32 = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));

        for (0..width) |x| {
            linear_buffer[y * width + x] = Linear.init(t * 0.8, t * 0.3, (1.0 - t) * 0.5, 1.0);
        }
    }

    const dither = Self{ .palette = pebble64 };

    // Reference: single-band (full height).
    var reference: [pixel_count]Srgb = undefined;
    var error_buffer: [errorBufferSize(width)]f32 = undefined;

    const full_band = try image.band(Linear, &linear_buffer, height, 0);

    _ = try dither.apply(full_band, &reference, &error_buffer);

    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output: [pixel_count]Srgb = undefined;
        var band_srgb_buffer: [pixel_count]Srgb = undefined;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;
            const band_linear = linear_buffer[row_start..][0..band_pixels];
            const narrow_band = try image.band(Linear, band_linear, band_height, band_index);

            const srgb_band = try dither.apply(
                narrow_band,
                band_srgb_buffer[0..band_pixels],
                &error_buffer,
            );

            @memcpy(banded_output[row_start..][0..band_pixels], srgb_band.buffer);
        }

        for (&reference, &banded_output, 0..) |ref, actual, i| {
            const y = i / width;
            const x = i % width;

            std.testing.expectEqual(ref.r, actual.r) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) r: expected {d}, got {d}\n",
                    .{ band_height, x, y, ref.r, actual.r },
                );

                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.g, actual.g) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) g: expected {d}, got {d}\n",
                    .{ band_height, x, y, ref.g, actual.g },
                );

                return error.TestUnexpectedResult;
            };

            std.testing.expectEqual(ref.b, actual.b) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) b: expected {d}, got {d}\n",
                    .{ band_height, x, y, ref.b, actual.b },
                );

                return error.TestUnexpectedResult;
            };
        }
    }
}

test "pebble64 is the 64-colour GColor8 cube with black first" {
    try std.testing.expectEqual(@as(usize, 64), pebble64.srgb_colors.len);
    try std.testing.expectEqual(@as(usize, 64), pebble64.oklab_colors.len);
    try std.testing.expectEqual(Srgb.black, pebble64.black());

    for (pebble64.srgb_colors, 0..) |color, i| {
        // Every channel is one of the four GColor8 levels.
        for ([_]u8{ color.r, color.g, color.b }) |channel| {
            try std.testing.expect(
                channel == 0 or channel == 85 or channel == 170 or channel == 255,
            );
        }

        // All entries are distinct.
        for (pebble64.srgb_colors[i + 1 ..]) |other| {
            try std.testing.expect(color.r != other.r or color.g != other.g or color.b != other.b);
        }
    }
}
