const app = @import("main.zig");

/// IMAGE_DEF block (must be in first 4 KiB of flash).
export const image_def linksection(".image_def") = [20]u8{
    // Block start marker
    0xD3, 0xDE, 0xFF, 0xFF,
    // IMAGE_TYPE item: type=0x42, size=1, data=0x1021 (EXE, ARM, secure, RP2350)
    0x42, 0x01, 0x21, 0x10,
    // LAST item: type=0xFF, size=0, padding
    0xFF, 0x00, 0x00, 0x00,
    // Block loop pointer (0 = single block, self-referencing)
    0x00, 0x00, 0x00, 0x00,
    // Block end marker
    0x79, 0x35, 0x12, 0xAB,
};

/// Cortex-M33 vector table.
const VectorTable = extern struct {
    initial_sp: u32,
    reset: *const fn () callconv(.c) noreturn,
    nmi: *const fn () callconv(.c) void = &defaultHandler,
    hard_fault: *const fn () callconv(.c) void = &defaultHandler,
    mem_manage: *const fn () callconv(.c) void = &defaultHandler,
    bus_fault: *const fn () callconv(.c) void = &defaultHandler,
    usage_fault: *const fn () callconv(.c) void = &defaultHandler,
    secure_fault: *const fn () callconv(.c) void = &defaultHandler,
    reserved_7: u32 = 0,
    reserved_8: u32 = 0,
    reserved_9: u32 = 0,
    svcall: *const fn () callconv(.c) void = &defaultHandler,
    debug_monitor: *const fn () callconv(.c) void = &defaultHandler,
    reserved_12: u32 = 0,
    pendsv: *const fn () callconv(.c) void = &defaultHandler,
    systick: *const fn () callconv(.c) void = &defaultHandler,
    irqs: [48]*const fn () callconv(.c) void = .{&defaultHandler} ** 48,
};

export const vector_table: VectorTable linksection(".vector_table") = .{
    .initial_sp = stack_top,
    .reset = &resetHandler,
};

fn defaultHandler() callconv(.c) void {
    while (true) {
        asm volatile ("wfi");
    }
}

extern var _bss_start: u32;
extern var _bss_end: u32;
extern var _data_start: u32;
extern var _data_end: u32;

extern const _data_load: u32;

const stack_top: u32 = 0x20082000; // Top of 520 KiB SRAM

/// Zeros .bss, copies .data from flash to SRAM, then calls main.
fn resetHandler() callconv(.c) noreturn {
    // Zero .bss
    const bss_start: [*]u8 = @ptrCast(&_bss_start);
    const bss_len = @intFromPtr(&_bss_end) - @intFromPtr(&_bss_start);

    @memset(bss_start[0..bss_len], 0);

    // Copy .data from flash to SRAM
    const data_start: [*]u8 = @ptrCast(&_data_start);
    const data_len = @intFromPtr(&_data_end) - @intFromPtr(&_data_start);
    const data_load: [*]const u8 = @ptrCast(&_data_load);

    @memcpy(data_start[0..data_len], data_load[0..data_len]);

    app.main();

    while (true) {
        asm volatile ("wfi");
    }
}
