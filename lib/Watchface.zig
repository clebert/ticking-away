const std = @import("std");

const Clock = @import("Clock.zig");
const Glow = @import("Glow.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Prism = @import("Prism.zig");
const Rainbow = @import("Rainbow.zig");
const Spectrum = @import("Spectrum.zig");
const Time = @import("Time.zig");

const Self = @This();

hand_glow_normalized_width: f32,
hand_glow_falloff: Glow.Falloff,
prism_glow_normalized_width: f32,
prism_glow_falloff: Glow.Falloff,
prism_glow_color: Linear,
rainbow_palette_id: Rainbow.PaletteId,

pub fn render(
    self: Self,
    band: *Image.Band(Linear),
    viewport: Image.Viewport,
    prism: Prism,
    clock: Clock,
) void {
    const right_side = clock.external_hour_hand.get(.green).end[0] > 0;
    const base_rainbow = Rainbow.get(self.rainbow_palette_id);
    const rainbow = if (right_side) base_rainbow.reversed() else base_rainbow;

    const hand_glow = Glow{
        .normalized_width = self.hand_glow_normalized_width,
        .falloff = self.hand_glow_falloff,
        .color = Linear.white,
    };

    // External minute hand (white light entering prism)
    hand_glow.renderLine(band, viewport, clock.external_minute_hand, .{
        .clip = .circle,
    });

    // Internal minute hand (bouncing inside prism)
    if (clock.internal_minute_hand) |internal_minute_hand| {
        hand_glow.renderLine(band, viewport, internal_minute_hand, .{
            .clip = .{ .prism = prism },
        });
    }

    // Internal hour rays (colored, fading toward prism edge)
    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const ray_glow = Glow{
            .normalized_width = self.hand_glow_normalized_width,
            .falloff = self.hand_glow_falloff,
            .color = rainbow.color(color_id),
        };

        ray_glow.renderLine(band, viewport, clock.internal_hour_hand.get(color_id), .{
            .clip = .{ .prism = prism },
            .fading = true,
        });
    }

    // Spectrum fill (rainbow gradient between rays)
    const external_spectrum = Spectrum.init(
        .external,
        .{ 0, 0 },
        clock.external_hour_hand.get(.red).end,
        clock.external_hour_hand.get(.violet).end,
    );

    external_spectrum.render(band, viewport, prism, rainbow);

    const internal_spectrum = Spectrum.init(
        .internal,
        clock.internal_hour_hand.get(.red).start,
        clock.internal_hour_hand.get(.red).end,
        clock.internal_hour_hand.get(.violet).end,
    );

    internal_spectrum.render(band, viewport, prism, rainbow);

    const prism_glow = Glow{
        .normalized_width = self.prism_glow_normalized_width,
        .falloff = self.prism_glow_falloff,
        .color = self.prism_glow_color,
    };

    prism_glow.renderPrismEdges(band, viewport, prism);
}

const test_image_size = 64;
const test_band_height = 8;
const test_band_count = test_image_size / test_band_height;

const test_prism = Prism.init(0.8);

const test_watchface = Self{
    .hand_glow_normalized_width = 0.005,
    .hand_glow_falloff = .quadratic,
    .prism_glow_normalized_width = 0.15,
    .prism_glow_falloff = .quadratic,
    .prism_glow_color = Linear.init(0.1, 0.75, 1.0, 1.0),
    .rainbow_palette_id = .oklch_balanced,
};

fn renderFull(time: Time) [test_image_size * test_image_size]Linear {
    const clock = Clock.init(time, test_prism, 0.5);
    const image = Image.init(test_image_size, test_image_size);
    const viewport = image.viewport();

    var full_buffer = [_]Linear{Linear.black} ** (test_image_size * test_image_size);
    var full_band = image.band(Linear, &full_buffer, test_image_size, 0) catch unreachable;

    test_watchface.render(&full_band, viewport, test_prism, clock);

    return full_buffer;
}

test "multi-band render matches single-band render" {
    const time = Time{ .total_minutes = 195.0 };
    const clock = Clock.init(time, test_prism, 0.5);
    const image = Image.init(test_image_size, test_image_size);
    const viewport = image.viewport();

    const reference_buffer = renderFull(time);

    var band_buffer: [test_image_size * test_band_height]Linear = undefined;

    for (0..test_band_count) |band_index| {
        @memset(&band_buffer, Linear.black);

        var narrow_band =
            image.band(Linear, &band_buffer, test_band_height, band_index) catch unreachable;

        test_watchface.render(&narrow_band, viewport, test_prism, clock);

        const row_start = band_index * test_image_size * test_band_height;

        for (
            band_buffer,
            reference_buffer[row_start..][0 .. test_image_size * test_band_height],
        ) |actual, expected| {
            try std.testing.expectApproxEqAbs(expected.vec[0], actual.vec[0], 1e-6);
            try std.testing.expectApproxEqAbs(expected.vec[1], actual.vec[1], 1e-6);
            try std.testing.expectApproxEqAbs(expected.vec[2], actual.vec[2], 1e-6);
        }
    }
}

test "render produces visible output at 3:15" {
    const buffer = renderFull(.{ .total_minutes = 195.0 });

    var sum: f64 = 0;

    for (&buffer) |pixel| {
        sum += pixel.vec[0] + pixel.vec[1] + pixel.vec[2];
    }

    try std.testing.expect(sum > 0);
}

test "render produces rainbow colors" {
    const buffer = renderFull(.{ .total_minutes = 195.0 });

    var has_red = false;
    var has_green = false;
    var has_blue = false;

    for (&buffer) |pixel| {
        if (pixel.vec[0] > 0.1 and pixel.vec[0] > pixel.vec[1] * 2 and pixel.vec[0] > pixel.vec[2] * 2) has_red = true;
        if (pixel.vec[1] > 0.1 and pixel.vec[1] > pixel.vec[0] * 2 and pixel.vec[1] > pixel.vec[2] * 2) has_green = true;
        if (pixel.vec[2] > 0.1 and pixel.vec[2] > pixel.vec[0] * 2 and pixel.vec[2] > pixel.vec[1] * 2) has_blue = true;
    }

    try std.testing.expect(has_red);
    try std.testing.expect(has_green);
    try std.testing.expect(has_blue);
}

test "render survives full 12-hour cycle" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 30.0) {
        _ = &renderFull(.{ .total_minutes = minutes });
    }
}
