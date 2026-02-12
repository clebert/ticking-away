const std = @import("std");

const Linear = @import("Linear.zig");
const Srgb = @import("Srgb.zig");

const Self = @This();

width: usize,
height: usize,

pub fn init(width: usize, height: usize) Self {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);

    return .{ .width = width, .height = height };
}

pub const Rotation = enum {
    none,
    clockwise_90,
};

pub fn Viewport(comptime rotation: Rotation) type {
    return struct {
        scale: f32,
        inverse_scale: f32,
        center: @Vector(2, f32),

        const forward_90cw = [2]@Vector(2, f32){ .{ 0, 1 }, .{ -1, 0 } };
        const inverse_90cw = [2]@Vector(2, f32){ .{ 0, -1 }, .{ 1, 0 } };

        pub fn toPixel(self: @This(), point: @Vector(2, f32)) @Vector(2, f32) {
            const unrotated = switch (rotation) {
                .none => point,
                .clockwise_90 => @Vector(2, f32){
                    @reduce(.Add, inverse_90cw[0] * point),
                    @reduce(.Add, inverse_90cw[1] * point),
                },
            };

            return unrotated * @as(@Vector(2, f32), @splat(self.scale)) + self.center;
        }

        pub fn toNormalized(self: @This(), pixel: @Vector(2, f32)) @Vector(2, f32) {
            const centered = (pixel - self.center) * @as(@Vector(2, f32), @splat(self.inverse_scale));

            return switch (rotation) {
                .none => centered,
                .clockwise_90 => @Vector(2, f32){
                    @reduce(.Add, forward_90cw[0] * centered),
                    @reduce(.Add, forward_90cw[1] * centered),
                },
            };
        }
    };
}

pub fn viewport(self: Self) Viewport(.none) {
    return self.viewportRotated(.none);
}

pub fn viewportRotated(self: Self, comptime rotation: Rotation) Viewport(rotation) {
    const width: f32 = @floatFromInt(self.width);
    const height: f32 = @floatFromInt(self.height);
    const scale = @min(width, height) / 2.0;

    return .{
        .scale = scale,
        .inverse_scale = 1.0 / scale,
        .center = .{ width / 2.0, height / 2.0 },
    };
}

pub fn Band(comptime Color: type) type {
    return struct {
        buffer: []Color,
        width: usize,
        y_offset: usize,

        pub fn bandHeight(self: Band(Color)) usize {
            return self.buffer.len / self.width;
        }

        pub fn imageY(self: Band(Color), y: usize) usize {
            return self.y_offset + y;
        }

        pub fn colorAt(self: Band(Color), x: usize, y: usize) *Color {
            return &self.buffer[y * self.width + x];
        }

        pub fn toSrgb(self: Band(Linear), srgb_buffer: []Srgb) !Band(Srgb) {
            if (self.buffer.len != srgb_buffer.len) {
                return error.BufferSizeMismatch;
            }

            for (self.buffer, srgb_buffer) |linear, *srgb| {
                srgb.* = linear.toSrgb();
            }

            return .{ .buffer = srgb_buffer, .width = self.width, .y_offset = self.y_offset };
        }
    };
}

pub fn band(
    self: Self,
    comptime Color: type,
    buffer: []Color,
    band_height: usize,
    band_index: usize,
) !Band(Color) {
    if (self.height % band_height != 0) {
        return error.InvalidBandHeight;
    }

    if (buffer.len != self.width * band_height) {
        return error.BufferSizeMismatch;
    }

    return .{ .buffer = buffer, .width = self.width, .y_offset = band_index * band_height };
}

test "viewport uses smaller dimension as scale basis for square image" {
    const image = Self.init(100, 100);
    const test_viewport = image.viewport();

    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.scale, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 50.0), test_viewport.inverse_scale, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.center[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.center[1], 1e-6);
}

test "viewport uses smaller dimension as scale basis for wide image" {
    const image = Self.init(200, 100);
    const test_viewport = image.viewport();

    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.scale, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), test_viewport.center[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.center[1], 1e-6);
}

test "viewport uses smaller dimension as scale basis for tall image" {
    const image = Self.init(100, 200);
    const test_viewport = image.viewport();

    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.scale, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), test_viewport.center[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), test_viewport.center[1], 1e-6);
}

test "toPixel maps origin to center" {
    const image = Self.init(100, 100);
    const test_viewport = image.viewport();
    const pixel = test_viewport.toPixel(.{ 0, 0 });

    try std.testing.expectApproxEqAbs(@as(f32, 50.0), pixel[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), pixel[1], 1e-6);
}

test "toNormalized maps center to origin" {
    const image = Self.init(100, 100);
    const test_viewport = image.viewport();
    const point = test_viewport.toNormalized(.{ 50, 50 });

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), point[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), point[1], 1e-6);
}

test "toPixel and toNormalized are inverse operations" {
    const image = Self.init(200, 100);
    const test_viewport = image.viewport();
    const original: @Vector(2, f32) = .{ 0.3, -0.7 };
    const round_trip = test_viewport.toNormalized(test_viewport.toPixel(original));

    try std.testing.expectApproxEqAbs(original[0], round_trip[0], 1e-5);
    try std.testing.expectApproxEqAbs(original[1], round_trip[1], 1e-5);
}

test "rotated viewport maps center pixel to origin" {
    const image = Self.init(120, 160);
    const test_viewport = image.viewportRotated(.clockwise_90);
    const point = test_viewport.toNormalized(.{ 60, 80 });

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), point[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), point[1], 1e-6);
}

test "rotated viewport toPixel maps origin to center" {
    const image = Self.init(120, 160);
    const test_viewport = image.viewportRotated(.clockwise_90);
    const pixel = test_viewport.toPixel(.{ 0, 0 });

    try std.testing.expectApproxEqAbs(@as(f32, 60.0), pixel[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), pixel[1], 1e-6);
}

test "rotated viewport toPixel and toNormalized are inverse operations" {
    const image = Self.init(120, 160);
    const test_viewport = image.viewportRotated(.clockwise_90);
    const original: @Vector(2, f32) = .{ 0.3, -0.7 };
    const round_trip = test_viewport.toNormalized(test_viewport.toPixel(original));

    try std.testing.expectApproxEqAbs(original[0], round_trip[0], 1e-5);
    try std.testing.expectApproxEqAbs(original[1], round_trip[1], 1e-5);
}

test "rotated viewport applies 90 degree clockwise rotation" {
    const image = Self.init(120, 160);
    const test_viewport = image.viewportRotated(.clockwise_90);

    // Pixel at center-right (120, 80) should map to normalized (0, -1) (top of circle)
    // centered = (60/60, 0/60) = (1, 0), rotated 90° CW: (0, -1)
    const point = test_viewport.toNormalized(.{ 120, 80 });

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), point[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), point[1], 1e-5);
}

test "band returns correct y_offset" {
    const image = Self.init(10, 100);

    var linear_buffer: [50]Linear = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 5, 3);

    try std.testing.expectEqual(@as(usize, 15), linear_band.y_offset);
    try std.testing.expectEqual(@as(usize, 10), linear_band.width);
}

test "band returns error for indivisible band height" {
    const image = Self.init(10, 100);

    var linear_buffer: [30]Linear = undefined;

    const result = image.band(Linear, &linear_buffer, 3, 0);

    try std.testing.expectError(error.InvalidBandHeight, result);
}

test "band returns error for wrong buffer size" {
    const image = Self.init(10, 100);

    var linear_buffer: [40]Linear = undefined;

    const result = image.band(Linear, &linear_buffer, 5, 0);

    try std.testing.expectError(error.BufferSizeMismatch, result);
}

test "bandHeight returns buffer rows" {
    const image = Self.init(10, 100);

    var linear_buffer: [50]Linear = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 5, 0);

    try std.testing.expectEqual(@as(usize, 5), linear_band.bandHeight());
}

test "imageY adds y_offset" {
    const image = Self.init(10, 100);

    var linear_buffer: [50]Linear = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 5, 2);

    try std.testing.expectEqual(@as(usize, 10), linear_band.imageY(0));
    try std.testing.expectEqual(@as(usize, 13), linear_band.imageY(3));
}

test "colorAt returns pointer to correct pixel" {
    const image = Self.init(4, 4);

    var linear_buffer = [_]Linear{Linear.black} ** 8;
    var linear_band = try image.band(Linear, &linear_buffer, 2, 0);

    linear_band.colorAt(2, 1).* = Linear.white;

    try std.testing.expectEqual(Linear.white.vec, linear_buffer[6].vec);
}

test "toSrgb converts all pixels" {
    const image = Self.init(2, 2);

    var linear_buffer = [_]Linear{ Linear.black, Linear.white, Linear.black, Linear.white };
    var srgb_buffer: [4]Srgb = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 2, 0);
    const srgb_band = try linear_band.toSrgb(&srgb_buffer);

    try std.testing.expectEqual(Srgb.black, srgb_band.buffer[0]);
    try std.testing.expectEqual(Srgb.white, srgb_band.buffer[1]);
    try std.testing.expectEqual(Srgb.black, srgb_band.buffer[2]);
    try std.testing.expectEqual(Srgb.white, srgb_band.buffer[3]);
}

test "toSrgb returns error for mismatched buffer size" {
    const image = Self.init(2, 2);

    var linear_buffer = [_]Linear{ Linear.black, Linear.white, Linear.black, Linear.white };
    var srgb_buffer: [2]Srgb = undefined;

    const linear_band = try image.band(Linear, &linear_buffer, 2, 0);
    const result = linear_band.toSrgb(&srgb_buffer);

    try std.testing.expectError(error.BufferSizeMismatch, result);
}
