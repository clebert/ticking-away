/// Converts an ELF binary to UF2 (USB Flashing Format) for the RP2350.
///
/// The Zig linker produces an ELF file when cross-compiling for the Pico 2's
/// Cortex-M33. The Pico's USB bootloader (BOOTSEL mode) expects a UF2 file,
/// which splits the binary into 512-byte blocks, each carrying 256 bytes of
/// payload and metadata (target flash address, block count, family ID).
///
/// This tool is built for the host machine and run as a post-link step by the
/// build system (see build.zig).
///
const std = @import("std");

const uf2_magic_start: u32 = 0x0A324655;
const uf2_magic_second: u32 = 0x9E5D5157;
const uf2_magic_end: u32 = 0x0AB16F30;
const uf2_flag_family_id: u32 = 0x00002000;
const rp2350_arm_s_family_id: u32 = 0xe48bff59;
const payload_size: u32 = 256;
const block_size: u32 = 512;

const Segment = struct {
    file_offset: u32,
    physical_address: u32,
    file_size: u32,
};

pub fn main() !void {
    var args = std.process.args();

    _ = args.next();

    const elf_path = args.next() orelse return error.MissingElfPath;
    const uf2_path = args.next() orelse return error.MissingUf2Path;

    const elf_file = try std.fs.cwd().openFile(elf_path, .{});

    defer elf_file.close();

    // Read ELF32 header (ARM Cortex-M produces 32-bit ELF)
    var ehdr_bytes: [@sizeOf(std.elf.Elf32_Ehdr)]u8 = undefined;

    if (try elf_file.readAll(&ehdr_bytes) != ehdr_bytes.len) return error.UnexpectedEof;

    const ehdr = std.mem.bytesAsValue(std.elf.Elf32_Ehdr, &ehdr_bytes);

    if (!std.mem.eql(u8, ehdr.e_ident[0..4], "\x7fELF")) return error.InvalidElf;
    if (ehdr.e_ident[std.elf.EI_CLASS] != std.elf.ELFCLASS32) return error.InvalidElfClass;
    if (ehdr.e_ident[std.elf.EI_DATA] != std.elf.ELFDATA2LSB) return error.InvalidElfEndian;
    if (ehdr.e_machine != .ARM) return error.InvalidElfMachine;

    // Iterate program headers, collect PT_LOAD segments
    var segments: [16]Segment = undefined;
    var segment_count: usize = 0;

    for (0..ehdr.e_phnum) |index| {
        try elf_file.seekTo(ehdr.e_phoff + index * @sizeOf(std.elf.Elf32_Phdr));

        var phdr_bytes: [@sizeOf(std.elf.Elf32_Phdr)]u8 = undefined;

        if (try elf_file.readAll(&phdr_bytes) != phdr_bytes.len) return error.UnexpectedEof;

        const phdr = std.mem.bytesAsValue(std.elf.Elf32_Phdr, &phdr_bytes);

        if (phdr.p_type != std.elf.PT_LOAD) continue;
        if (phdr.p_filesz == 0) continue;
        if (segment_count >= segments.len) return error.TooManySegments;

        segments[segment_count] = .{
            .file_offset = phdr.p_offset,
            .physical_address = phdr.p_paddr,
            .file_size = phdr.p_filesz,
        };

        segment_count += 1;
    }

    // Count total 256-byte pages
    var total_blocks: u32 = 0;

    for (segments[0..segment_count]) |segment| {
        total_blocks += (segment.file_size + payload_size - 1) / payload_size;
    }

    const uf2_file = try std.fs.cwd().createFile(uf2_path, .{});

    defer uf2_file.close();

    // Write UF2 blocks
    var block_number: u32 = 0;

    for (segments[0..segment_count]) |segment| {
        var offset: u32 = 0;

        while (offset < segment.file_size) {
            const chunk_size = @min(payload_size, segment.file_size - offset);

            var block = std.mem.zeroes([block_size]u8);

            std.mem.writeInt(u32, block[0..4], uf2_magic_start, .little);
            std.mem.writeInt(u32, block[4..8], uf2_magic_second, .little);
            std.mem.writeInt(u32, block[8..12], uf2_flag_family_id, .little);
            std.mem.writeInt(u32, block[12..16], segment.physical_address + offset, .little);
            std.mem.writeInt(u32, block[16..20], payload_size, .little);
            std.mem.writeInt(u32, block[20..24], block_number, .little);
            std.mem.writeInt(u32, block[24..28], total_blocks, .little);
            std.mem.writeInt(u32, block[28..32], rp2350_arm_s_family_id, .little);

            try elf_file.seekTo(segment.file_offset + offset);

            if (try elf_file.readAll(block[32..][0..chunk_size]) != chunk_size)
                return error.UnexpectedEof;

            std.mem.writeInt(u32, block[508..512], uf2_magic_end, .little);

            try uf2_file.writeAll(&block);

            offset += payload_size;
            block_number += 1;
        }
    }
}
