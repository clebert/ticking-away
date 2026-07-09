const std = @import("std");

const Image = @import("Image.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

outside_color: Srgb,
antialias: bool = false,

pub fn apply(self: Self, band: Image.Band(Srgb), viewport: anytype) void {
    const radius = viewport.scale - 1.0;
    const center_x = viewport.center[0];
    const center_y = viewport.center[1];

    for (0..band.height()) |local_y| {
        const y: f32 = @floatFromInt(band.imageY(local_y));
        const delta_y = y + 0.5 - center_y;
        const row = band.buffer[local_y * band.width ..][0..band.width];

        if (self.antialias) {
            self.applyAntialiasedRow(row, center_x, delta_y, radius);
        } else {
            self.applyHardRow(row, center_x, delta_y, radius);
        }
    }
}

fn applyHardRow(self: Self, row: []Srgb, center_x: f32, delta_y: f32, radius: f32) void {
    const delta_x_max_squared = radius * radius - delta_y * delta_y;

    if (delta_x_max_squared < 0.0) {
        @memset(row, self.outside_color);

        return;
    }

    const delta_x_max = @sqrt(delta_x_max_squared);
    const x_low = center_x - 0.5 - delta_x_max;
    const x_high = center_x - 0.5 + delta_x_max;

    // @ceil keeps the left/right margins symmetric.
    const x_start: usize = if (x_low < 0) 0 else @intFromFloat(@ceil(x_low));

    const x_end: usize = @min(
        if (x_high < 0) 0 else @as(usize, @intFromFloat(x_high)) + 1,
        row.len,
    );

    if (x_start > 0) {
        @memset(row[0..x_start], self.outside_color);
    }

    if (x_end < row.len) {
        @memset(row[x_end..row.len], self.outside_color);
    }
}

// A pixel is fully covered within radius - 0.5 of the centre and fully outside beyond
// radius + 0.5; the one-pixel band between is the antialiased rim. Grading every covered
// pixel by its own coverage smooths the whole rim: along the near-horizontal top and bottom
// arcs the partially covered pixels span the middle of a row, not only its edges.
fn applyAntialiasedRow(self: Self, row: []Srgb, center_x: f32, delta_y: f32, radius: f32) void {
    const outer = radius + 0.5;
    const outer_squared = outer * outer - delta_y * delta_y;

    if (outer_squared <= 0.0) {
        @memset(row, self.outside_color);

        return;
    }

    const outer_delta_x = @sqrt(outer_squared);
    const covered_low = center_x - 0.5 - outer_delta_x;
    const covered_high = center_x - 0.5 + outer_delta_x;

    const covered_start: usize = if (covered_low < 0) 0 else @intFromFloat(@floor(covered_low));

    const covered_end: usize = @min(
        if (covered_high < 0) 0 else @as(usize, @intFromFloat(@floor(covered_high))) + 1,
        row.len,
    );

    if (covered_start > 0) {
        @memset(row[0..covered_start], self.outside_color);
    }

    if (covered_end < row.len) {
        @memset(row[covered_end..row.len], self.outside_color);
    }

    const inner = radius - 0.5;
    const inner_squared = inner * inner - delta_y * delta_y;

    if (inner_squared <= 0.0) {
        // Near the top and bottom of the circle the rim spans the whole covered run with no
        // fully opaque core, so every covered pixel belongs to the antialiased arc.
        self.blendRim(row, center_x, delta_y, radius, covered_start, covered_end);

        return;
    }

    const inner_delta_x = @sqrt(inner_squared);
    const core_low = center_x - 0.5 - inner_delta_x;
    const core_high = center_x - 0.5 + inner_delta_x;

    const core_start: usize = if (core_low < 0) 0 else @intFromFloat(@ceil(core_low));

    const core_end: usize = @min(
        if (core_high < 0) 0 else @as(usize, @intFromFloat(@floor(core_high))) + 1,
        row.len,
    );

    self.blendRim(row, center_x, delta_y, radius, covered_start, @min(core_start, covered_end));
    self.blendRim(row, center_x, delta_y, radius, @max(core_end, covered_start), covered_end);
}

fn blendRim(
    self: Self,
    row: []Srgb,
    center_x: f32,
    delta_y: f32,
    radius: f32,
    from: usize,
    to: usize,
) void {
    for (from..to) |x| {
        const coverage = pixelCoverage(center_x, delta_y, radius, x);

        if (coverage >= 1.0) continue;

        if (coverage <= 0.0) {
            row[x] = self.outside_color;

            continue;
        }

        self.blendPixel(&row[x], coverage);
    }
}

fn pixelCoverage(center_x: f32, delta_y: f32, radius: f32, x: usize) f32 {
    const delta_x = @as(f32, @floatFromInt(x)) + 0.5 - center_x;
    const distance = @sqrt(delta_x * delta_x + delta_y * delta_y);

    return std.math.clamp(radius - distance + 0.5, 0.0, 1.0);
}

fn blendPixel(self: Self, pixel: *Srgb, coverage: f32) void {
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
        const t: u8 = @intCast(@divFloor(y * 255, height - 1));

        for (0..width) |x| {
            const s: u8 = @intCast(@divFloor(x * 255, width - 1));

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
        const band_count = @divExact(height, band_height);

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
            const y = @divFloor(i, width);
            const x = i % width;

            std.testing.expectEqual(ref, actual) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) " ++
                        "expected ({d},{d},{d},{d}), got ({d},{d},{d},{d})\n",
                    .{
                        band_height,
                        x,
                        y,
                        ref.r,
                        ref.g,
                        ref.b,
                        ref.a,
                        actual.r,
                        actual.g,
                        actual.b,
                        actual.a,
                    },
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

test "antialias grades the entire near-horizontal top arc" {
    const size = 128;
    const image = Image.init(size, size);
    const viewport = image.viewport();

    var buffer = [_]Srgb{Srgb.white} ** (size * size);

    const band = try image.band(Srgb, &buffer, size, 0);
    const crop = Self{ .outside_color = Srgb.transparent, .antialias = true };

    crop.apply(band, viewport);

    var y_top: usize = 0;

    outer: while (y_top < size) : (y_top += 1) {
        for (0..size) |x| {
            if (buffer[y_top * size + x].a != 0) break :outer;
        }
    }

    var graded_count: usize = 0;
    var opaque_count: usize = 0;

    for (0..size) |x| {
        const alpha = buffer[y_top * size + x].a;

        if (alpha == 0) continue;

        if (alpha == 255) {
            opaque_count += 1;
        } else {
            graded_count += 1;
        }
    }

    // The topmost covered row is a graded arc: nearly every covered pixel is partially
    // transparent, and only the apex can round to full opacity (at most a couple of pixels).
    try std.testing.expect(graded_count > 4);
    try std.testing.expect(opaque_count <= 2);
}

test "multi-band antialias crop matches single-band" {
    const width = 16;
    const height = 48;
    const image = Image.init(width, height);
    const viewport = image.viewport();
    const pixel_count = width * height;

    var input: [pixel_count]Srgb = undefined;

    for (0..height) |y| {
        const t: u8 = @intCast(@divFloor(y * 255, height - 1));

        for (0..width) |x| {
            const s: u8 = @intCast(@divFloor(x * 255, width - 1));

            input[y * width + x] = .{ .r = t, .g = s, .b = 128 };
        }
    }

    const crop = Self{ .outside_color = Srgb.transparent, .antialias = true };

    var reference = input;

    const full_band = try image.band(Srgb, &reference, height, 0);

    crop.apply(full_band, viewport);

    const band_heights = [_]usize{ 1, 2, 3, 4, 8, 16 };

    for (band_heights) |band_height| {
        const band_count = @divExact(height, band_height);

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
            const y = @divFloor(i, width);
            const x = i % width;

            std.testing.expectEqual(ref, actual) catch {
                std.debug.print(
                    "band_height={d}: mismatch at ({d},{d}) " ++
                        "expected ({d},{d},{d},{d}), got ({d},{d},{d},{d})\n",
                    .{
                        band_height,
                        x,
                        y,
                        ref.r,
                        ref.g,
                        ref.b,
                        ref.a,
                        actual.r,
                        actual.g,
                        actual.b,
                        actual.a,
                    },
                );

                return error.TestUnexpectedResult;
            };
        }
    }
}
