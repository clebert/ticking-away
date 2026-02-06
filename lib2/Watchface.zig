const std = @import("std");

const Clock = @import("Clock.zig");
const Glow = @import("Glow.zig");
const Image = @import("Image.zig");
const Linear = @import("Linear.zig");
const Rainbow = @import("Rainbow.zig");
const Scene = @import("Scene.zig");
const Spectrum = @import("Spectrum.zig");

const Self = @This();

hand_glow_style: Glow.Style,
rainbow_palette_id: Rainbow.PaletteId,

pub fn render(self: Self, band: *Image.Band(Linear), viewport: Image.Viewport, scene: Scene, clock: Clock) void {
    const rainbow = Rainbow.get(self.rainbow_palette_id);

    // External minute hand (white light entering prism)
    const external_minute_glow = Glow{
        .style = self.hand_glow_style,
        .color = Linear.white,
        .clip_radius = scene.radius,
    };

    external_minute_glow.renderLine(band, viewport, clock.external_minute_hand);

    // Internal minute hand (bouncing inside prism)
    if (clock.internal_minute_hand) |internal_minute_hand| {
        const internal_minute_glow = Glow{
            .style = self.hand_glow_style,
            .color = Linear.white,
        };

        internal_minute_glow.renderLine(band, viewport, internal_minute_hand);
    }

    // Internal hour rays (colored, fading toward prism edge)
    for (std.enums.values(Rainbow.ColorId)) |color_id| {
        const internal_hour_glow = Glow{
            .style = self.hand_glow_style,
            .color = rainbow.color(color_id),
            .intensity = .{ .gradient = .{ .start = 1.0, .end = 0.0 } },
        };

        internal_hour_glow.renderLine(band, viewport, clock.internal_hour_hand.get(color_id));
    }

    // Spectrum fill (rainbow gradient between rays)
    Spectrum.render(band, viewport, scene, clock, rainbow);
}
