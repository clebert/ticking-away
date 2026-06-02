// PNG encoder; compresses image data with deflate at its best level.

const std = @import("std");

const lib = @import("lib");

const signature = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

pub fn write(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    width: usize,
    height: usize,
    pixels: []const lib.Srgb,
) !void {
    const scanlines = try filterScanlines(allocator, width, height, pixels);

    defer allocator.free(scanlines);

    const compressed = try zlibDeflate(allocator, scanlines);

    defer allocator.free(compressed);

    const file = try std.Io.Dir.cwd().createFile(io, path, .{});

    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var buffered = file.writer(io, &buffer);

    const writer = &buffered.interface;

    try writer.writeAll(&signature);
    try writeChunk(writer, "IHDR", &encodeHeader(width, height));
    try writeChunk(writer, "IDAT", compressed);
    try writeChunk(writer, "IEND", &.{});
    try writer.flush();
}

/// Prepends each row with a filter byte (0 = None) and flattens pixels to RGBA bytes.
fn filterScanlines(
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    pixels: []const lib.Srgb,
) ![]u8 {
    const row_bytes = 1 + width * 4;
    const data = try allocator.alloc(u8, height * row_bytes);

    for (0..height) |y| {
        const row_start = y * row_bytes;

        data[row_start] = 0;

        const row = pixels[y * width ..][0..width];

        for (row, 0..) |pixel, x| {
            const offset = row_start + 1 + x * 4;

            data[offset] = pixel.r;
            data[offset + 1] = pixel.g;
            data[offset + 2] = pixel.b;
            data[offset + 3] = pixel.a;
        }
    }

    return data;
}

/// Compresses data into a zlib stream RFC 1950. Returned slice owned by caller.
fn zlibDeflate(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const window = try allocator.alloc(u8, std.compress.flate.max_window_len);

    defer allocator.free(window);

    var output: std.Io.Writer.Allocating = try .initCapacity(allocator, data.len / 2 + 64);

    errdefer output.deinit();

    var compress = try std.compress.flate.Compress.init(&output.writer, window, .zlib, .best);

    try compress.writer.writeAll(data);
    try compress.finish();

    return output.toOwnedSlice();
}

fn writeChunk(writer: *std.Io.Writer, chunk_type: *const [4]u8, data: []const u8) !void {
    var length_bytes: [4]u8 = undefined;

    std.mem.writeInt(u32, &length_bytes, @intCast(data.len), .big);

    try writer.writeAll(&length_bytes);

    try writer.writeAll(chunk_type);

    if (data.len > 0) {
        try writer.writeAll(data);
    }

    var crc: std.hash.crc.Crc32 = .init();

    crc.update(chunk_type);
    crc.update(data);

    var crc_bytes: [4]u8 = undefined;

    std.mem.writeInt(u32, &crc_bytes, crc.final(), .big);

    try writer.writeAll(&crc_bytes);
}

fn encodeHeader(width: usize, height: usize) [13]u8 {
    var data: [13]u8 = undefined;

    std.mem.writeInt(u32, data[0..4], @intCast(width), .big);
    std.mem.writeInt(u32, data[4..8], @intCast(height), .big);

    data[8] = 8; // bit depth
    data[9] = 6; // color type: RGBA
    data[10] = 0; // compression: deflate
    data[11] = 0; // filter: adaptive
    data[12] = 0; // interlace: none

    return data;
}
