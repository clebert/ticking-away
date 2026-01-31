const std = @import("std");
const lib = @import("lib");

const color = lib.color;
const grain = lib.grain;

test "grain hash deterministic" {
    // Same coordinates should produce same hash
    const h1 = grain.hashPixel(100, 200);
    const h2 = grain.hashPixel(100, 200);
    try std.testing.expectEqual(h1, h2);

    // Different coordinates should produce different hash
    const h3 = grain.hashPixel(101, 200);
    try std.testing.expect(h1 != h3);
}

test "grain apply" {
    var buffer = [_]color.Color{
        color.rgb(0.5, 0.5, 0.5),
        color.rgb(0.5, 0.5, 0.5),
        color.rgb(0.5, 0.5, 0.5),
        color.rgb(0.5, 0.5, 0.5),
    };

    const config = grain.Config{ .intensity = 1.0, .scale = 1.0, .threshold = 0.1 };
    grain.apply(&buffer, 2, 2, config, null);

    // Values should have changed but still be valid
    for (buffer) |c| {
        try std.testing.expect(c[0] >= 0.0 and c[0] <= 1.0);
        try std.testing.expect(c[1] >= 0.0 and c[1] <= 1.0);
        try std.testing.expect(c[2] >= 0.0 and c[2] <= 1.0);
    }
}
