const std = @import("std");

const Image = @import("Image.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

color: Srgb,

pub fn apply(self: Self, band: *Image.Band(Srgb), viewport: Image.Viewport) void {
    const radius_squared = viewport.scale * viewport.scale;
    const center_x = viewport.center[0];
    const center_y = viewport.center[1];

    for (0..band.bandHeight()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));
        const dy = y + 0.5 - center_y;
        const dx_max_squared = radius_squared - dy * dy;

        const row = band.buffer[local_y * band.width ..][0..band.width];

        if (dx_max_squared < 0.0) {
            @memset(row, self.color);

            continue;
        }

        const dx_max = @sqrt(dx_max_squared);
        const x_lo = center_x - 0.5 - dx_max;
        const x_hi = center_x - 0.5 + dx_max;
        const x_start: usize = if (x_lo < 0) 0 else @intFromFloat(x_lo);

        const x_end: usize = @min(
            if (x_hi < 0) 0 else @as(usize, @intFromFloat(x_hi)) + 1,
            band.width,
        );

        if (x_start > 0) {
            @memset(row[0..x_start], self.color);
        }

        if (x_end < band.width) {
            @memset(row[x_end..band.width], self.color);
        }
    }
}

test "apply sets pixels outside circle to background color" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 100;
    var band = image.band(Srgb, &buffer, 10, 0) catch unreachable;

    const background = Self{ .color = Srgb.white };

    background.apply(&band, viewport);

    // Corner pixel (0,0) is outside the unit circle — should be white
    try std.testing.expectEqual(Srgb.white, buffer[0]);

    // Center pixel (5,5) is inside the unit circle — should stay black
    try std.testing.expectEqual(Srgb.black, buffer[5 * 10 + 5]);
}

test "apply sets transparent background" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 100;
    var band = image.band(Srgb, &buffer, 10, 0) catch unreachable;

    const background = Self{ .color = Srgb.transparent };

    background.apply(&band, viewport);

    // Corner pixel should be transparent
    try std.testing.expectEqual(@as(u8, 0), buffer[0].a);

    // Center pixel should remain opaque (default alpha=255)
    try std.testing.expectEqual(@as(u8, 255), buffer[5 * 10 + 5].a);
}

test "apply handles wide image" {
    const image = Image.init(20, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 200;
    var band = image.band(Srgb, &buffer, 10, 0) catch unreachable;

    const background = Self{ .color = Srgb.white };

    background.apply(&band, viewport);

    // Far left pixel (0,5) is outside circle in a wide image (circle radius = 5)
    try std.testing.expectEqual(Srgb.white, buffer[5 * 20 + 0]);

    // Far right pixel (19,5) is also outside
    try std.testing.expectEqual(Srgb.white, buffer[5 * 20 + 19]);

    // Center pixel (10,5) is inside
    try std.testing.expectEqual(Srgb.black, buffer[5 * 20 + 10]);
}
