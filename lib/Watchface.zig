const std = @import("std");

const Clock = @import("Clock.zig");
const Glow = @import("Glow.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Rainbow = @import("Rainbow.zig");
const Ray = @import("Ray.zig");
const Spectrum = @import("Spectrum.zig");
const Time = @import("Time.zig");

const Self = @This();

hand_glow_normalized_width: f32,
prism_glow_normalized_width: f32,

// One coherent album blue for the whole prism — its edge glow, the internal
// beam, and the ray inside it. Matched to patch averages of the Dark Side of
// the Moon cover (its analog grain averaged out): a saturated blue with green
// well above red, so the glow reads blue rather than grey.
const prism_tint = Linear.init(0.03, 0.34, 0.52, 1.0);

pub fn render(self: Self, band: Image.Band(Linear), viewport: anytype, clock: Clock) void {
    const right_side = clock.hour_hand.get(.green).end[0] > 0;
    const rainbow = if (right_side) Rainbow.dark_side_of_the_moon.reversed() else Rainbow.dark_side_of_the_moon;

    const hand_glow = Glow{
        .normalized_width = self.hand_glow_normalized_width,
        .color = Linear.white,
    };

    const minute_ray = Ray.init(clock.minute_hand.start, clock.minute_hand.end);
    const minute_intersection = clock.prism.intersect(minute_ray) orelse unreachable;

    const attenuation_origin =
        clock.minute_hand.project(minute_intersection.hit).normalized_position;

    hand_glow.renderLine(
        band,
        viewport,
        clock.minute_hand,
        attenuation_origin,
        prism_tint,
    );

    const spectrum = Spectrum.init(
        .{ 0, 0 },
        clock.hour_hand.get(.red).end,
        clock.hour_hand.get(.violet).end,
    );

    const hour_ray = Ray.init(.{ 0, 0 }, clock.hour_hand.get(.green).end);
    const hour_intersection = clock.prism.intersect(hour_ray) orelse unreachable;

    spectrum.render(
        band,
        viewport,
        rainbow,
        hour_intersection.distance,
        clock.prism,
        prism_tint,
    );

    const prism_glow = Glow{
        .normalized_width = self.prism_glow_normalized_width,
        .color = prism_tint,
    };

    prism_glow.renderPrismEdges(band, viewport, clock.prism);
}

const test_image_size = 64;
const test_band_height = 8;
const test_band_count = test_image_size / test_band_height;

const test_prism_normalized_size: f32 = 0.8;

const test_watchface = Self{
    .hand_glow_normalized_width = 0.005,
    .prism_glow_normalized_width = 0.15,
};

fn renderFull(time: Time) [test_image_size * test_image_size]Linear {
    const clock = Clock.init(time, test_prism_normalized_size, 0.5);
    const image = Image.init(test_image_size, test_image_size);
    const viewport = image.viewport();

    var full_buffer = [_]Linear{Linear.black} ** (test_image_size * test_image_size);

    const full_band = image.band(Linear, &full_buffer, test_image_size, 0) catch unreachable;

    test_watchface.render(full_band, viewport, clock);

    return full_buffer;
}

test "multi-band render matches single-band render" {
    const time = Time{ .total_minutes = 195.0 };
    const clock = Clock.init(time, test_prism_normalized_size, 0.5);
    const image = Image.init(test_image_size, test_image_size);
    const viewport = image.viewport();

    const reference_buffer = renderFull(time);

    var band_buffer: [test_image_size * test_band_height]Linear = undefined;

    for (0..test_band_count) |band_index| {
        @memset(&band_buffer, Linear.black);

        const narrow_band =
            try image.band(Linear, &band_buffer, test_band_height, band_index);

        test_watchface.render(narrow_band, viewport, clock);

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
        if (pixel.vec[0] > 0.1 and
            pixel.vec[0] > pixel.vec[1] * 2 and
            pixel.vec[0] > pixel.vec[2] * 2) has_red = true;

        if (pixel.vec[1] > 0.1 and
            pixel.vec[1] > pixel.vec[0] * 2 and
            pixel.vec[1] > pixel.vec[2] * 2) has_green = true;

        if (pixel.vec[2] > 0.1 and
            pixel.vec[2] > pixel.vec[0] * 2 and
            pixel.vec[2] > pixel.vec[1] * 2) has_blue = true;
    }

    try std.testing.expect(has_red);
    try std.testing.expect(has_green);
    try std.testing.expect(has_blue);
}

test "render survives full 12-hour cycle" {
    var minutes: f32 = 0.0;

    while (minutes < 720.0) : (minutes += 30.0) {
        // The & prevents the compiler from optimizing away the call
        _ = &renderFull(.{ .total_minutes = minutes });
    }
}
