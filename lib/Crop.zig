const std = @import("std");

const Image = @import("Image.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

outside_color: Srgb,
antialias: bool = false,

pub fn apply(self: Self, band: Image.Band(Srgb), viewport: anytype) void {
    const radius = viewport.scale - 1.0;
    const radius_squared = radius * radius;
    const center_x = viewport.center[0];
    const center_y = viewport.center[1];

    for (0..band.bandHeight()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));
        const dy = y + 0.5 - center_y;
        const dx_max_squared = radius_squared - dy * dy;

        const row = band.buffer[local_y * band.width ..][0..band.width];

        if (dx_max_squared < 0.0) {
            @memset(row, self.outside_color);

            if (self.antialias) {
                self.antialiasNearEdge(row, center_x, dy, radius);
            }

            continue;
        }

        const dx_max = @sqrt(dx_max_squared);
        const x_low = center_x - 0.5 - dx_max;
        const x_high = center_x - 0.5 + dx_max;

        // @ceil keeps the left/right margins symmetric.
        const x_start: usize = if (x_low < 0) 0 else @intFromFloat(@ceil(x_low));

        const x_end: usize = @min(
            if (x_high < 0) 0 else @as(usize, @intFromFloat(x_high)) + 1,
            band.width,
        );

        if (x_start > 0) {
            @memset(row[0..x_start], self.outside_color);
        }

        if (x_end < band.width) {
            @memset(row[x_end..band.width], self.outside_color);
        }

        if (self.antialias) {
            self.antialiasAtBoundary(row, center_x, dy, radius, x_start, x_end);
        }
    }
}

fn antialiasAtBoundary(
    self: Self,
    row: []Srgb,
    center_x: f32,
    dy: f32,
    radius: f32,
    x_start: usize,
    x_end: usize,
) void {
    const left_from = if (x_start > 1) x_start - 1 else 0;
    const left_to = @min(x_start + 1, row.len);

    for (left_from..left_to) |x| {
        self.blendPixel(&row[x], pixelCoverage(center_x, dy, radius, x));
    }

    const right_from = if (x_end > 1) x_end - 1 else 0;
    const right_to = @min(x_end + 1, row.len);

    for (right_from..right_to) |x| {
        if (x >= left_from and x < left_to) continue;

        self.blendPixel(&row[x], pixelCoverage(center_x, dy, radius, x));
    }
}

fn antialiasNearEdge(self: Self, row: []Srgb, center_x: f32, dy: f32, radius: f32) void {
    // Rows just outside the circle still have partially covered pixels near the top/bottom arc.
    const outer = radius + 0.5;
    const dx_max_squared = outer * outer - dy * dy;
    if (dx_max_squared < 0.0) return;

    const dx_max = @sqrt(dx_max_squared);
    const x_low = center_x - 0.5 - dx_max;
    const x_high = center_x - 0.5 + dx_max;

    const from: usize = if (x_low < 0) 0 else @intFromFloat(@floor(x_low));

    const to: usize =
        @min(if (x_high < 0) 0 else @as(usize, @intFromFloat(@ceil(x_high))) + 1, row.len);

    for (from..to) |x| {
        self.blendPixel(&row[x], pixelCoverage(center_x, dy, radius, x));
    }
}

fn pixelCoverage(center_x: f32, dy: f32, radius: f32, x: usize) f32 {
    const dx = @as(f32, @floatFromInt(x)) + 0.5 - center_x;
    const distance = @sqrt(dx * dx + dy * dy);

    return std.math.clamp(radius - distance + 0.5, 0.0, 1.0);
}

fn blendPixel(self: Self, pixel: *Srgb, coverage: f32) void {
    if (coverage >= 1.0 or coverage <= 0.0) return;

    const inverse_coverage = 1.0 - coverage;

    pixel.* = .{
        .r = lerpByte(self.outside_color.r, pixel.r, coverage, inverse_coverage),
        .g = lerpByte(self.outside_color.g, pixel.g, coverage, inverse_coverage),
        .b = lerpByte(self.outside_color.b, pixel.b, coverage, inverse_coverage),
        .a = lerpByte(self.outside_color.a, pixel.a, coverage, inverse_coverage),
    };
}

fn lerpByte(a: u8, b: u8, t: f32, inverse_t: f32) u8 {
    return @intFromFloat(@round(
        @as(f32, @floatFromInt(a)) * inverse_t + @as(f32, @floatFromInt(b)) * t,
    ));
}

test "apply sets pixels outside circle to outside color" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 100;

    const band = try image.band(Srgb, &buffer, 10, 0);
    const crop = Self{ .outside_color = Srgb.white };

    crop.apply(band, viewport);

    try std.testing.expectEqual(Srgb.white, buffer[0]);

    try std.testing.expectEqual(Srgb.black, buffer[5 * 10 + 5]);
}

test "apply sets transparent outside color" {
    const image = Image.init(10, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 100;

    const band = try image.band(Srgb, &buffer, 10, 0);
    const crop = Self{ .outside_color = Srgb.transparent };

    crop.apply(band, viewport);

    try std.testing.expectEqual(@as(u8, 0), buffer[0].a);

    try std.testing.expectEqual(@as(u8, 255), buffer[5 * 10 + 5].a);
}

test "apply handles wide image" {
    const image = Image.init(20, 10);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.black} ** 200;

    const band = try image.band(Srgb, &buffer, 10, 0);
    const crop = Self{ .outside_color = Srgb.white };

    crop.apply(band, viewport);

    try std.testing.expectEqual(Srgb.white, buffer[5 * 20 + 0]);

    try std.testing.expectEqual(Srgb.white, buffer[5 * 20 + 19]);

    try std.testing.expectEqual(Srgb.black, buffer[5 * 20 + 10]);
}

test "multi-band crop matches single-band crop" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const viewport = image.viewport();
    const pixel_count = width * height;

    var input: [pixel_count]Srgb = undefined;

    for (0..height) |y| {
        const t: u8 = @intCast(y * 255 / (height - 1));

        for (0..width) |x| {
            const s: u8 = @intCast(x * 255 / (width - 1));

            input[y * width + x] = .{ .r = t, .g = s, .b = 128 };
        }
    }

    const crop = Self{ .outside_color = .{ .r = 20, .g = 30, .b = 40 } };

    var reference = input;

    const full_band = try image.band(Srgb, &reference, height, 0);

    crop.apply(full_band, viewport);

    // Cover extreme (1), odd, and even band heights
    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            const narrow_band = try image.band(
                Srgb,
                banded_output[row_start..][0..band_pixels],
                band_height,
                band_index,
            );

            crop.apply(narrow_band, viewport);
        }

        for (&reference, &banded_output, 0..) |ref, actual, i| {
            const y = i / width;
            const x = i % width;

            std.testing.expectEqual(ref, actual) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) expected ({d},{d},{d},{d}), got ({d},{d},{d},{d})\n",
                    .{ band_height, x, y, ref.r, ref.g, ref.b, ref.a, actual.r, actual.g, actual.b, actual.a },
                );

                return error.TestUnexpectedResult;
            };
        }
    }
}

test "antialias produces intermediate alpha at circle edge" {
    const image = Image.init(20, 20);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.white} ** 400;

    const band = try image.band(Srgb, &buffer, 20, 0);
    const crop = Self{ .outside_color = Srgb.transparent, .antialias = true };

    crop.apply(band, viewport);

    try std.testing.expectEqual(@as(u8, 255), buffer[10 * 20 + 10].a);

    try std.testing.expectEqual(@as(u8, 0), buffer[0].a);

    var found_intermediate = false;

    for (0..20) |x| {
        const a = buffer[10 * 20 + x].a;

        if (a > 0 and a < 255) {
            found_intermediate = true;
            break;
        }
    }

    try std.testing.expect(found_intermediate);
}

test "multi-band antialias crop matches single-band" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const viewport = image.viewport();
    const pixel_count = width * height;

    var input: [pixel_count]Srgb = undefined;

    for (0..height) |y| {
        const t: u8 = @intCast(y * 255 / (height - 1));

        for (0..width) |x| {
            const s: u8 = @intCast(x * 255 / (width - 1));

            input[y * width + x] = .{ .r = t, .g = s, .b = 128 };
        }
    }

    const crop = Self{ .outside_color = Srgb.transparent, .antialias = true };

    var reference = input;

    const full_band = try image.band(Srgb, &reference, height, 0);

    crop.apply(full_band, viewport);

    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = height / band_height;

        var banded_output = input;

        for (0..band_count) |band_index| {
            const row_start = band_index * band_height * width;
            const band_pixels = band_height * width;

            const narrow_band = try image.band(
                Srgb,
                banded_output[row_start..][0..band_pixels],
                band_height,
                band_index,
            );

            crop.apply(narrow_band, viewport);
        }

        for (&reference, &banded_output, 0..) |ref, actual, i| {
            const y = i / width;
            const x = i % width;

            std.testing.expectEqual(ref, actual) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) expected ({d},{d},{d},{d}), got ({d},{d},{d},{d})\n",
                    .{ band_height, x, y, ref.r, ref.g, ref.b, ref.a, actual.r, actual.g, actual.b, actual.a },
                );

                return error.TestUnexpectedResult;
            };
        }
    }
}
