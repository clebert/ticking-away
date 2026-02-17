const hal = @import("hal.zig");

// GPIO pin assignments (Pico GP numbers via Waveshare Pico-To-HAT)
const pin_reset = 27;
const pin_dc = 22;
const pin_cs0 = 26;
const pin_cs1 = 16;

pub const ChipSelect = enum { cs0, cs1, both };

pub fn init() void {
    hal.initGpioOutput(pin_reset, true);
    hal.initGpioOutput(pin_dc, false);
    hal.initGpioOutput(pin_cs0, true);
    hal.initGpioOutput(pin_cs1, true);

    reset();
    initSequence();
}

pub fn beginData(cs: ChipSelect) void {
    sendCommand(0x10, cs, &.{});
    hal.gpioSetHigh(pin_dc);
    selectChip(cs);
}

pub fn writeData(data: []const u8) void {
    hal.spiWrite(data);
}

pub fn endData() void {
    deselectChips();
    hal.gpioSetLow(pin_dc);
}

pub fn refresh() void {
    sendCommand(0x04, .both, &.{}); // PON
    hal.sleepMs(300); // Boost converter settling time
    sendCommand(0x12, .both, &.{0x00}); // DRF
    sendCommand(0x02, .both, &.{0x00}); // POF
}

fn reset() void {
    hal.gpioSetLow(pin_reset);
    hal.sleepMs(30);
    hal.gpioSetHigh(pin_reset);
    hal.sleepMs(30);
}

fn initSequence() void {
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
}

fn sendCommand(command: u8, cs: ChipSelect, data: []const u8) void {
    selectChip(cs);
    hal.gpioSetLow(pin_dc);
    hal.spiWrite(&.{command});

    if (data.len > 0) {
        hal.gpioSetHigh(pin_dc);
        hal.spiWrite(data);
    }

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
