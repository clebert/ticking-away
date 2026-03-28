const app = @import("main.zig");
const hal = @import("hal.zig");

export const image_def linksection(".image_def") = [28]u8{
    0xD3, 0xDE, 0xFF, 0xFF, // Block start
    0x42, 0x01, 0x21, 0x10, // IMAGE_TYPE: EXE, ARM, secure, RP2350
    0x03, 0x02, 0x00, 0x00, // VECTOR_TABLE item
    0x00, 0x01, 0x00, 0x10, // Vector table at 0x10000100
    0xFF, 0x03, 0x00, 0x00, // LAST item
    0x00, 0x00, 0x00, 0x00, // Block loop pointer
    0x79, 0x35, 0x12, 0xAB, // Block end
};

const VectorTable = extern struct {
    initial_sp: u32,
    reset: *const fn () callconv(.naked) noreturn,
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
    .initial_sp = 0x20082000,
    .reset = &resetHandler,
    .hard_fault = @ptrCast(&faultEntry),
    .mem_manage = @ptrCast(&faultEntry),
    .bus_fault = @ptrCast(&faultEntry),
    .usage_fault = @ptrCast(&faultEntry),
};

fn defaultHandler() callconv(.c) void {
    while (true) asm volatile ("wfi");
}

fn faultEntry() callconv(.naked) noreturn {
    asm volatile (
        \\ mrs r0, msp
        \\ b faultHandlerImpl
    );
}

export fn faultHandlerImpl(frame: [*]const u32) callconv(.c) noreturn {
    const resets_done: *volatile u32 = @ptrFromInt(0x40020008);
    if ((resets_done.* & (1 << 26)) != 0) {
        hal.uartPrint("\n=== FAULT ===\n");
        hal.uartPrint("CFSR: ");
        hal.uartPrintHex(@as(*volatile u32, @ptrFromInt(0xE000ED28)).*);
        hal.uartPrint("\nHFSR: ");
        hal.uartPrintHex(@as(*volatile u32, @ptrFromInt(0xE000ED2C)).*);
        hal.uartPrint("\nBFAR: ");
        hal.uartPrintHex(@as(*volatile u32, @ptrFromInt(0xE000ED38)).*);
        hal.uartPrint("\nPC:   ");
        hal.uartPrintHex(frame[6]);
        hal.uartPrint("\nLR:   ");
        hal.uartPrintHex(frame[5]);
        hal.uartPrint("\n");
        hal.uartFlush();
    }
    const gpio_out_xor: *volatile u32 = @ptrFromInt(0xD0000028);
    const gpio_oe_set: *volatile u32 = @ptrFromInt(0xD0000038);
    gpio_oe_set.* = 1 << 25;
    while (true) {
        gpio_out_xor.* = 1 << 25;
        for (0..200_000) |_| asm volatile ("nop");
    }
}

extern var _bss_start: u32;
extern var _bss_end: u32;
extern var _data_start: u32;
extern var _data_end: u32;
extern const _data_load: u32;

fn resetHandler() callconv(.naked) noreturn {
    asm volatile (
        \\ movw r0, #0x2000
        \\ movt r0, #0x2008
        \\ mov sp, r0
        \\ movw r0, #0xED88
        \\ movt r0, #0xE000
        \\ ldr r1, [r0]
        \\ orr r1, r1, #(0xF << 20)
        \\ str r1, [r0]
        \\ dsb
        \\ isb
        \\ b initRuntime
    );
}

export fn initRuntime() callconv(.c) noreturn {
    const bss: [*]volatile u8 = @ptrCast(&_bss_start);
    const bss_len = @intFromPtr(&_bss_end) - @intFromPtr(&_bss_start);
    if (bss_len > 0) {
        var i: usize = 0;
        while (i < bss_len) : (i += 1) {
            bss[i] = 0;
        }
    }

    const data: [*]volatile u8 = @ptrCast(&_data_start);
    const data_len = @intFromPtr(&_data_end) - @intFromPtr(&_data_start);
    const data_load: [*]const volatile u8 = @ptrCast(&_data_load);
    if (data_len > 0) {
        var i: usize = 0;
        while (i < data_len) : (i += 1) {
            data[i] = data_load[i];
        }
    }

    app.main();

    while (true) asm volatile ("wfi");
}

// AEABI wrappers — needed if compiler emits memcpy/memset calls
export fn __aeabi_memcpy(dest: [*]u8, src: [*]const u8, n: usize) callconv(.c) void {
    copyForward(dest, src, n);
}
export fn __aeabi_memcpy4(dest: [*]u8, src: [*]const u8, n: usize) callconv(.c) void {
    copyForward(dest, src, n);
}
export fn __aeabi_memcpy8(dest: [*]u8, src: [*]const u8, n: usize) callconv(.c) void {
    copyForward(dest, src, n);
}
export fn __aeabi_memmove(dest: [*]u8, src: [*]const u8, n: usize) callconv(.c) void {
    copyForward(dest, src, n);
}
export fn __aeabi_memmove4(dest: [*]u8, src: [*]const u8, n: usize) callconv(.c) void {
    copyForward(dest, src, n);
}
export fn __aeabi_memmove8(dest: [*]u8, src: [*]const u8, n: usize) callconv(.c) void {
    copyForward(dest, src, n);
}
export fn __aeabi_memset(dest: [*]u8, n: usize, val: i32) callconv(.c) void {
    fill(dest, n, @truncate(@as(u32, @bitCast(val))));
}
export fn __aeabi_memset4(dest: [*]u8, n: usize, val: i32) callconv(.c) void {
    fill(dest, n, @truncate(@as(u32, @bitCast(val))));
}
export fn __aeabi_memset8(dest: [*]u8, n: usize, val: i32) callconv(.c) void {
    fill(dest, n, @truncate(@as(u32, @bitCast(val))));
}
export fn __aeabi_memclr(dest: [*]u8, n: usize) callconv(.c) void {
    fill(dest, n, 0);
}
export fn __aeabi_memclr4(dest: [*]u8, n: usize) callconv(.c) void {
    fill(dest, n, 0);
}
export fn __aeabi_memclr8(dest: [*]u8, n: usize) callconv(.c) void {
    fill(dest, n, 0);
}

noinline fn copyForward(dest: [*]u8, src: [*]const u8, n: usize) void {
    const vd: [*]volatile u8 = @ptrCast(dest);
    const vs: [*]const volatile u8 = @ptrCast(src);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        vd[i] = vs[i];
    }
}

noinline fn fill(dest: [*]u8, n: usize, val: u8) void {
    const vd: [*]volatile u8 = @ptrCast(dest);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        vd[i] = val;
    }
}
