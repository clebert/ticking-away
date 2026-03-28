// RP2350 peripheral base addresses
const xosc_base = 0x40048000;
const pll_sys_base = 0x40050000;
const clocks_base = 0x40010000;
const resets_base = 0x40020000;
const io_bank0_base = 0x40028000;
const pads_bank0_base = 0x40038000;
const sio_base = 0xD0000000;
const spi1_base = 0x40088000;
const uart0_base = 0x40070000;
const timer0_base = 0x400B0000;
const ticks_base = 0x40108000;

const atomic_set = 0x2000;
const atomic_clr = 0x3000;

fn reg(address: u32) *volatile u32 {
    return @ptrFromInt(address);
}

pub fn initClocks() void {
    // Safe clock teardown (idempotent for warm reboots)
    reg(clocks_base + 0x3C).* = 0; // CLK_SYS → clk_ref
    busyDelay();
    reg(clocks_base + 0x30).* = 0x00; // CLK_REF → ROSC
    busyDelay();
    reg(ticks_base + 0x10).* = 0; // Disable TICKS_TIMER0

    // Start XOSC (12 MHz crystal)
    reg(xosc_base + 0x00).* = 0xAA0; // FREQ_RANGE = 1-15 MHz
    reg(xosc_base + 0x0C).* = 47; // STARTUP delay
    reg(xosc_base + atomic_set + 0x00).* = 0xFAB << 12; // ENABLE
    while ((reg(xosc_base + 0x04).* & (1 << 31)) == 0) {}

    busyDelay();

    // CLK_REF → XOSC
    reg(clocks_base + 0x30).* = 0x02;

    // Reset + configure PLL_SYS: 12 MHz * 125 / 5 / 2 = 150 MHz
    reg(resets_base + atomic_set + 0x00).* = 1 << 14;
    reg(resets_base + atomic_clr + 0x00).* = 1 << 14;
    while ((reg(resets_base + 0x08).* & (1 << 14)) == 0) {}

    reg(pll_sys_base + 0x08).* = 125; // FBDIV
    reg(pll_sys_base + atomic_clr + 0x04).* = (1 << 0) | (1 << 5); // PD + VCOPD
    while ((reg(pll_sys_base + 0x00).* & (1 << 31)) == 0) {} // LOCK

    busyDelay();

    reg(pll_sys_base + 0x0C).* = (5 << 16) | (2 << 12); // Post-dividers
    reg(pll_sys_base + atomic_clr + 0x04).* = 1 << 3; // POSTDIVPD

    // CLK_SYS → PLL_SYS
    reg(clocks_base + 0x40).* = 1 << 16; // DIV = 1
    reg(clocks_base + 0x3C).* = (0 << 5) | 1; // AUXSRC=PLL_SYS, SRC=aux

    busyDelay();

    // CLK_PERI from CLK_SYS
    reg(clocks_base + 0x48).* = 1 << 11;

    // Unreset IO_BANK0(6) + PADS_BANK0(9)
    const io_pads_bits: u32 = (1 << 6) | (1 << 9);
    reg(resets_base + atomic_clr + 0x00).* = io_pads_bits;
    while ((reg(resets_base + 0x08).* & io_pads_bits) != io_pads_bits) {}

    // Force-reset then unreset SPI1(19) + Timer0(23)
    const spi_timer_bits: u32 = (1 << 19) | (1 << 23);
    reg(resets_base + atomic_set + 0x00).* = spi_timer_bits;
    reg(resets_base + atomic_clr + 0x00).* = spi_timer_bits;
    while ((reg(resets_base + 0x08).* & spi_timer_bits) != spi_timer_bits) {}

    // Timer0 tick: 12 MHz / 12 = 1 MHz
    reg(ticks_base + 0x14).* = 12;
    reg(ticks_base + 0x10).* = 1;
}

pub fn initGpioOutput(pin: u5, high: bool) void {
    reg(pads_bank0_base + atomic_clr + 0x04 + @as(u32, pin) * 4).* = 1 << 8; // Clear ISO
    reg(io_bank0_base + 0x04 + @as(u32, pin) * 8).* = 5; // FUNCSEL = SIO
    if (high) {
        reg(sio_base + 0x018).* = @as(u32, 1) << pin;
    } else {
        reg(sio_base + 0x020).* = @as(u32, 1) << pin;
    }
    reg(sio_base + 0x038).* = @as(u32, 1) << pin; // OE_SET
}

pub fn initGpioInput(pin: u5) void {
    const pad = pads_bank0_base + 0x04 + @as(u32, pin) * 4;
    reg(pad + atomic_clr).* = (1 << 8) | (1 << 2); // Clear ISO + pull-down
    reg(pad + atomic_set).* = 1 << 3; // Pull-up
    reg(io_bank0_base + 0x04 + @as(u32, pin) * 8).* = 5; // FUNCSEL = SIO
}

pub fn gpioRead(pin: u5) bool {
    return (reg(sio_base + 0x004).* & (@as(u32, 1) << pin)) != 0;
}

pub fn gpioSetHigh(pin: u5) void {
    reg(sio_base + 0x018).* = @as(u32, 1) << pin;
}

pub fn gpioSetLow(pin: u5) void {
    reg(sio_base + 0x020).* = @as(u32, 1) << pin;
}

pub fn initSpi() void {
    // GP10 = SPI1 SCK, GP11 = SPI1 TX
    reg(pads_bank0_base + atomic_clr + 0x04 + 10 * 4).* = 1 << 8; // Clear ISO
    reg(io_bank0_base + 0x04 + 10 * 8).* = 1; // FUNCSEL = SPI
    reg(pads_bank0_base + atomic_clr + 0x04 + 11 * 4).* = 1 << 8;
    reg(io_bank0_base + 0x04 + 11 * 8).* = 1;

    // 8-bit, mode 0, SCR=14 -> 150 MHz / (2 * 15) = 5 MHz
    reg(spi1_base + 0x00).* = (14 << 8) | 0x07;
    reg(spi1_base + 0x10).* = 2; // CPSDVSR = 2
    reg(spi1_base + 0x04).* = 1 << 1; // SSE = 1
}

pub fn spiWrite(data: []const u8) void {
    for (data) |byte| {
        while ((reg(spi1_base + 0x0C).* & (1 << 1)) == 0) {}
        reg(spi1_base + 0x08).* = byte;
    }
    while ((reg(spi1_base + 0x0C).* & (1 << 4)) != 0) {}
    while ((reg(spi1_base + 0x0C).* & (1 << 2)) != 0) {
        _ = reg(spi1_base + 0x08).*;
    }
}

// --- UART0 on GP0 at 115200 baud ---

pub fn initUart() void {
    const uart_bit: u32 = 1 << 26;
    reg(resets_base + atomic_set + 0x00).* = uart_bit; // Force reset
    reg(resets_base + atomic_clr + 0x00).* = uart_bit;
    while ((reg(resets_base + 0x08).* & uart_bit) == 0) {}

    reg(pads_bank0_base + atomic_clr + 0x04).* = 1 << 8; // Clear ISO on GP0
    reg(io_bank0_base + 0x04).* = 2; // GP0 FUNCSEL = UART0_TX

    // 115200 baud @ 150 MHz: 150e6 / (16 * 115200) = 81.38
    reg(uart0_base + 0x24).* = 81;
    reg(uart0_base + 0x28).* = 24; // 0.38 * 64

    reg(uart0_base + 0x2C).* = (0b11 << 5) | (1 << 4); // 8N1, FIFO enable
    reg(uart0_base + 0x30).* = (1 << 0) | (1 << 8); // UART + TX enable
}

pub fn uartWriteByte(byte: u8) void {
    while ((reg(uart0_base + 0x18).* & (1 << 5)) != 0) {}
    reg(uart0_base + 0x00).* = byte;
}

pub fn uartPrint(str: []const u8) void {
    for (str) |byte| {
        if (byte == '\n') uartWriteByte('\r');
        uartWriteByte(byte);
    }
}

pub fn uartPrintHex(value: u32) void {
    const hex = "0123456789ABCDEF";
    uartPrint("0x");
    var shift: u5 = 28;
    while (true) {
        const nibble: u4 = @truncate(value >> shift);
        uartWriteByte(hex[nibble]);
        if (shift == 0) break;
        shift -= 4;
    }
}

pub fn uartFlush() void {
    while (true) {
        const flags = reg(uart0_base + 0x18).*;
        if ((flags & (1 << 7)) != 0 and (flags & (1 << 3)) == 0) break;
    }
}

// --- Timing ---

pub fn sleepUs(microseconds: u32) void {
    const start = reg(timer0_base + 0x28).*;
    while (reg(timer0_base + 0x28).* -% start < microseconds) {}
}

pub fn sleepMs(milliseconds: u32) void {
    var remaining = milliseconds;
    while (remaining > 0) : (remaining -= 1) {
        sleepUs(1000);
    }
}

// --- LED helpers ---

pub fn earlyBlink(count: u32) void {
    const io_pads_bits: u32 = (1 << 6) | (1 << 9);
    reg(resets_base + atomic_clr + 0x00).* = io_pads_bits;
    while ((reg(resets_base + 0x08).* & io_pads_bits) != io_pads_bits) {}

    initGpioOutput(25, false);
    for (0..count) |_| {
        gpioSetHigh(25);
        busyDelay();
        gpioSetLow(25);
        busyDelay();
    }
    busyDelay();
    busyDelay();
}

pub fn blink(count: u32) void {
    initGpioOutput(25, false);
    for (0..count) |_| {
        gpioSetHigh(25);
        fastBusyDelay();
        gpioSetLow(25);
        fastBusyDelay();
    }
    fastBusyDelay();
    fastBusyDelay();
}

fn busyDelay() void {
    for (0..400_000) |_| asm volatile ("nop");
}

fn fastBusyDelay() void {
    for (0..10_000_000) |_| asm volatile ("nop");
}
