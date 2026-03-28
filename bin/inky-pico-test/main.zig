const hal = @import("hal.zig");

const pin_reset: u5 = 2;
const pin_busy: u5 = 3;
const pin_dc: u5 = 4;
const pin_cs0: u5 = 5;
const pin_cs1: u5 = 6;

comptime {
    _ = @import("boot.zig");
}

pub const panic = @import("std").debug.FullPanic(panicHandler);

fn panicHandler(msg: []const u8, _: ?usize) noreturn {
    const resets_done: *volatile u32 = @ptrFromInt(0x40020008);
    if ((resets_done.* & (1 << 26)) != 0) {
        hal.uartPrint("\n=== PANIC: ");
        hal.uartPrint(msg);
        hal.uartPrint(" ===\n");
        hal.uartFlush();
    }
    while (true) asm volatile ("wfi");
}

pub fn main() void {
    hal.earlyBlink(1);
    hal.initClocks();
    hal.initUart();
    hal.initSpi();

    hal.uartPrint("\n=== Inky Test ===\n");

    // Init display GPIOs
    hal.uartPrint("gpio init\n");
    hal.initGpioOutput(pin_reset, true);
    hal.initGpioInput(pin_busy);
    hal.initGpioOutput(pin_dc, false);
    hal.initGpioOutput(pin_cs0, true);
    hal.initGpioOutput(pin_cs1, true);

    printBusy("initial");

    // Reset display
    hal.uartPrint("reset\n");
    hal.gpioSetLow(pin_reset);
    hal.sleepMs(30);
    hal.gpioSetHigh(pin_reset);
    hal.sleepMs(30);

    printBusy("post-reset");

    // Init sequence (identical to inky-zero, confirmed working on Linux)
    hal.uartPrint("init sequence\n");
    sendCommand(0x74, .cs0, &.{ 0xC0, 0x1C, 0x1C, 0xCC, 0xCC, 0xCC, 0x15, 0x15, 0x55 });
    sendCommand(0xF0, .both, &.{ 0x49, 0x55, 0x13, 0x5D, 0x05, 0x10 });
    sendCommand(0x00, .both, &.{ 0xDF, 0x69 });
    sendCommand(0x30, .both, &.{0x08});
    sendCommand(0x50, .both, &.{0xF7});
    sendCommand(0x60, .both, &.{ 0x03, 0x03 });
    sendCommand(0x86, .both, &.{0x10});
    sendCommand(0xE3, .both, &.{0x22});
    sendCommand(0xE0, .both, &.{0x01});
    sendCommand(0x61, .both, &.{ 0x04, 0xB0, 0x03, 0x20 });
    sendCommand(0x01, .cs0, &.{ 0x0F, 0x00, 0x28, 0x2C, 0x28, 0x38 });
    sendCommand(0xB6, .cs0, &.{0x07});
    sendCommand(0x06, .cs0, &.{ 0xD8, 0x18 });
    sendCommand(0xB7, .cs0, &.{0x01});
    sendCommand(0x05, .cs0, &.{ 0xD8, 0x18 });
    sendCommand(0xB0, .cs0, &.{0x01});
    sendCommand(0xB1, .cs0, &.{0x02});

    printBusy("post-init");

    // CS0=red, CS1=blue — move CS1 wire to display pin 37 (same as CS0) to test
    hal.uartPrint("fill red CS0\n");
    fillController(.cs0, 0x33);
    hal.uartPrint("fill blue CS1\n");
    fillController(.cs1, 0x55);

    printBusy("post-data");

    // Refresh
    hal.uartPrint("PON\n");
    sendCommand(0x04, .both, &.{});
    printBusy("after-PON");
    hal.sleepMs(300);
    printBusy("after-PON-wait");

    hal.uartPrint("DRF\n");
    sendCommand(0x12, .both, &.{0x00});
    printBusy("after-DRF");

    // Wait for refresh (e-ink takes ~30-40 seconds)
    hal.uartPrint("waiting 40s for refresh...\n");
    hal.uartFlush();
    hal.sleepMs(40_000);
    printBusy("after-wait");

    hal.uartPrint("POF\n");
    sendCommand(0x02, .both, &.{0x00});

    hal.blink(3);
    hal.uartPrint("done\n");

    while (true) asm volatile ("wfi");
}

fn fillController(cs: ChipSelect, color: u8) void {
    sendCommand(0x10, cs, &.{});
    hal.gpioSetHigh(pin_dc);
    selectChip(cs);
    hal.sleepUs(1);

    // 1600 rows x 600 columns, 2 pixels per byte = 480,000 bytes
    var row_buf: [300]u8 = .{color} ** 300;
    var row: u32 = 0;
    while (row < 1600) : (row += 1) {
        hal.spiWrite(&row_buf);
    }

    hal.sleepUs(1);
    deselectChips();
    hal.gpioSetLow(pin_dc);
}

const ChipSelect = enum { cs0, cs1, both };

fn sendCommand(command: u8, cs: ChipSelect, data: []const u8) void {
    selectChip(cs);
    hal.gpioSetLow(pin_dc);
    hal.sleepUs(1);
    hal.spiWrite(&.{command});

    if (data.len > 0) {
        hal.gpioSetHigh(pin_dc);
        hal.sleepUs(1);
        hal.spiWrite(data);
    }

    hal.sleepUs(1);
    deselectChips();
    hal.gpioSetLow(pin_dc);
}

fn selectChip(cs: ChipSelect) void {
    switch (cs) {
        .cs0 => {
            hal.gpioSetLow(pin_cs0);
            hal.gpioSetHigh(pin_cs1);
        },
        .cs1 => {
            hal.gpioSetHigh(pin_cs0);
            hal.gpioSetLow(pin_cs1);
        },
        .both => {
            hal.gpioSetLow(pin_cs0);
            hal.gpioSetLow(pin_cs1);
        },
    }
}

fn deselectChips() void {
    hal.gpioSetHigh(pin_cs0);
    hal.gpioSetHigh(pin_cs1);
}

fn printBusy(label: []const u8) void {
    hal.uartPrint("  BUSY[");
    hal.uartPrint(label);
    hal.uartPrint("]: ");
    hal.uartPrint(if (hal.gpioRead(pin_busy)) "HIGH" else "LOW");
    hal.uartPrint("\n");
}
