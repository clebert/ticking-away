// PNG encoder using stored (uncompressed) deflate blocks.
//
// Zig 0.15.2's std.compress.flate.Compress has incomplete implementations,
// so we use the simplest valid deflate encoding: stored blocks (BTYPE=00).

const std = @import("std");

const lib = @import("lib");

const signature = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

pub fn write(
    allocator: std.mem.Allocator,
    path: []const u8,
    width: usize,
    height: usize,
    pixels: []const lib.Srgb,
) !void {
    const scanlines = try filterScanlines(allocator, width, height, pixels);

    defer allocator.free(scanlines);

    const compressed = try zlibStored(allocator, scanlines);

    defer allocator.free(compressed);

    const file = try std.fs.cwd().createFile(path, .{});

    defer file.close();

    var buffer: [8192]u8 = undefined;
    var buffered = file.writer(&buffer);

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

/// Wraps data in a zlib stream using stored (uncompressed) deflate blocks.
/// Each stored block: 1-byte header + 2-byte LEN + 2-byte NLEN + up to 65535 bytes of data.
fn zlibStored(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const max_block_size = 65535;
    const block_count = if (data.len == 0) 1 else (data.len + max_block_size - 1) / max_block_size;
    const total_size = 2 + block_count * 5 + data.len + 4;

    const output = try allocator.alloc(u8, total_size);

    var position: usize = 0;

    // CMF=0x78 (deflate, window=32K), FLG=0x01 (fastest, checksum valid)
    output[position] = 0x78;
    output[position + 1] = 0x01;
    position += 2;

    if (data.len == 0) {
        output[position] = 0x01;
        position += 1;
        std.mem.writeInt(u16, output[position..][0..2], 0, .little);
        position += 2;
        std.mem.writeInt(u16, output[position..][0..2], 0xFFFF, .little);
        position += 2;
    } else {
        var remaining = data.len;
        var offset: usize = 0;

        while (remaining > 0) {
            const block_size: u16 = @intCast(@min(remaining, max_block_size));
            const is_final = remaining <= max_block_size;

            output[position] = if (is_final) 0x01 else 0x00;
            position += 1;

            std.mem.writeInt(u16, output[position..][0..2], block_size, .little);
            position += 2;

            std.mem.writeInt(u16, output[position..][0..2], ~block_size, .little);
            position += 2;

            @memcpy(output[position..][0..block_size], data[offset..][0..block_size]);
            position += block_size;

            offset += block_size;
            remaining -= block_size;
        }
    }

    var adler: std.hash.Adler32 = .{};

    adler.update(data);
    std.mem.writeInt(u32, output[position..][0..4], adler.adler, .big);
    position += 4;

    return output[0..position];
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
