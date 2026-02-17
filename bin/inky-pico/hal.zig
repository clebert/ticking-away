// RP2350 peripheral base addresses
const xosc_base = 0x40048000;
const pll_sys_base = 0x40050000;
const clocks_base = 0x40010000;
const resets_base = 0x40020000;
const io_bank0_base = 0x40028000;
const sio_base = 0xD0000000;
const spi1_base = 0x40088000;
const timer0_base = 0x400B0000;
const powman_base = 0x40100000;

// Atomic register alias offsets (for APB/AHB peripherals, not SIO)
const atomic_set = 0x2000;
const atomic_clr = 0x3000;

const powman_password: u32 = 0x5AFE0000;

fn reg(address: u32) *volatile u32 {
    return @ptrFromInt(address);
}

/// Initializes clocks: XOSC → PLL_SYS 150 MHz → CLK_SYS → CLK_PERI.
pub fn initClocks() void {
    // Start XOSC (12 MHz crystal)
    reg(xosc_base + 0x00).* = 0xAA0; // CTRL: FREQ_RANGE = 1-15 MHz
    reg(xosc_base + 0x0C).* = 47; // STARTUP: ~1ms at 12 MHz (12000000/256)
    reg(xosc_base + atomic_set + 0x00).* = 0xFAB << 12; // CTRL: ENABLE
    while ((reg(xosc_base + 0x04).* & (1 << 31)) == 0) {} // Wait STATUS.STABLE

    // Switch CLK_REF to XOSC
    reg(clocks_base + 0x30).* = 0x02; // CLK_REF_CTRL: SRC = XOSC

    // Reset PLL_SYS
    reg(resets_base + atomic_set + 0x00).* = 1 << 14;
    reg(resets_base + atomic_clr + 0x00).* = 1 << 14;
    while ((reg(resets_base + 0x08).* & (1 << 14)) == 0) {} // Wait RESET_DONE

    // Configure PLL_SYS: 12 MHz * 125 / 5 / 2 = 150 MHz
    reg(pll_sys_base + 0x08).* = 125; // FBDIV_INT
    // Clear PD and VCOPD in PWR to power on VCO
    reg(pll_sys_base + atomic_clr + 0x04).* = (1 << 0) | (1 << 5);
    while ((reg(pll_sys_base + 0x00).* & (1 << 31)) == 0) {} // Wait CS.LOCK

    // Set post-dividers and enable them
    reg(pll_sys_base + 0x0C).* = (5 << 16) | (2 << 12); // PRIM: POSTDIV1=5, POSTDIV2=2
    reg(pll_sys_base + atomic_clr + 0x04).* = 1 << 3; // Clear POSTDIVPD

    // Switch CLK_SYS to PLL_SYS
    reg(clocks_base + 0x3C).* = 0; // CLK_SYS_CTRL: SRC=clk_ref (safe source while switching)
    reg(clocks_base + 0x40).* = 1 << 16; // CLK_SYS_DIV: INT=1
    reg(clocks_base + 0x3C).* = (0 << 5) | 1; // CLK_SYS_CTRL: AUXSRC=PLL_SYS, SRC=aux

    // Enable CLK_PERI from CLK_SYS
    reg(clocks_base + 0x48).* = 1 << 11; // CLK_PERI_CTRL: ENABLE, AUXSRC=clk_sys

    // Unreset peripherals: IO_BANK0(6), PADS_BANK0(9), SPI1(19), TIMER0(23)
    const peripheral_bits = (1 << 6) | (1 << 9) | (1 << 19) | (1 << 23);
    reg(resets_base + atomic_clr + 0x00).* = peripheral_bits;
    while ((reg(resets_base + 0x08).* & peripheral_bits) != peripheral_bits) {}
}

/// Pins 0-31 only; RP2350 interleaves HI registers for pins 32-47.
pub fn initGpioOutput(pin: u5, high: bool) void {
    // Set FUNCSEL to SIO (5) in IO_BANK0 GPIO_CTRL
    reg(io_bank0_base + 0x04 + @as(u32, pin) * 8).* = 5;
    // Set initial value
    if (high) {
        reg(sio_base + 0x018).* = @as(u32, 1) << pin; // GPIO_OUT_SET
    } else {
        reg(sio_base + 0x020).* = @as(u32, 1) << pin; // GPIO_OUT_CLR
    }
    // Enable output
    reg(sio_base + 0x038).* = @as(u32, 1) << pin; // GPIO_OE_SET
}

pub fn initGpioSpiFunction(pin: u5) void {
    reg(io_bank0_base + 0x04 + @as(u32, pin) * 8).* = 1; // FUNCSEL = SPI
}

pub fn gpioSetHigh(pin: u5) void {
    reg(sio_base + 0x018).* = @as(u32, 1) << pin;
}

pub fn gpioSetLow(pin: u5) void {
    reg(sio_base + 0x020).* = @as(u32, 1) << pin;
}

/// Initializes SPI1 (PL022-compatible, 9.375 MHz, mode 0, 8-bit).
pub fn initSpi() void {
    // Configure GP10 (SPI1 SCK) and GP11 (SPI1 TX) for SPI function
    initGpioSpiFunction(10);
    initGpioSpiFunction(11);

    // SSPCR0: 8-bit frames (DSS=7), SPI mode 0, SCR=7
    // Baud = CLK_PERI / (CPSDVSR * (1 + SCR)) = 150 MHz / (2 * 8) = 9.375 MHz
    reg(spi1_base + 0x00).* = (7 << 8) | 0x07; // SCR=7, SPO=0, SPH=0, FRF=0, DSS=7

    // SSPCPSR: prescale divisor = 2 (minimum, must be even)
    reg(spi1_base + 0x10).* = 2;

    // SSPCR1: enable SPI, master mode
    reg(spi1_base + 0x04).* = 1 << 1; // SSE=1
}

pub fn spiWrite(data: []const u8) void {
    for (data) |byte| {
        // Wait for TX FIFO not full
        while ((reg(spi1_base + 0x0C).* & (1 << 1)) == 0) {}
        reg(spi1_base + 0x08).* = byte;
    }
    // Wait for SPI idle
    while ((reg(spi1_base + 0x0C).* & (1 << 4)) != 0) {}
    // Drain RX FIFO
    while ((reg(spi1_base + 0x0C).* & (1 << 2)) != 0) {
        _ = reg(spi1_base + 0x08).*;
    }
}

/// Microsecond busy-wait using Timer0.
pub fn sleepUs(microseconds: u32) void {
    const start = reg(timer0_base + 0x28).*; // TIMERAWL
    while (reg(timer0_base + 0x28).* -% start < microseconds) {}
}

pub fn sleepMs(milliseconds: u32) void {
    sleepUs(milliseconds * 1000);
}

const powman_timer_reg = powman_base + 0x88;

// POWMAN timer register bit masks (from RP2350 datasheet section 6.7)
const timer_run: u32 = 1 << 1;
const timer_alarm_enab: u32 = 1 << 4;
const timer_alarm: u32 = 1 << 6;
const timer_use_lposc: u32 = 1 << 8;
const timer_use_xosc: u32 = 1 << 9;
const timer_using_xosc: u32 = 1 << 16;
const timer_using_lposc: u32 = 1 << 17;

pub fn isTimerRunning() bool {
    return (reg(powman_timer_reg).* & timer_run) != 0;
}

pub fn startTimer() void {
    reg(powman_timer_reg + atomic_set).* = timer_run;
}

pub fn setTimeMs(ms: u64) void {
    reg(powman_base + 0x60).* = powman_password | @as(u32, @as(u16, @truncate(ms >> 48)));
    reg(powman_base + 0x64).* = powman_password | @as(u32, @as(u16, @truncate(ms >> 32)));
    reg(powman_base + 0x68).* = powman_password | @as(u32, @as(u16, @truncate(ms >> 16)));
    reg(powman_base + 0x6C).* = powman_password | @as(u32, @as(u16, @truncate(ms)));
}

pub fn readTimeMs() u64 {
    // Read upper, lower, upper again to handle rollover
    while (true) {
        const upper1 = reg(powman_base + 0x70).*;
        const lower = reg(powman_base + 0x74).*;
        const upper2 = reg(powman_base + 0x70).*;
        if (upper1 == upper2) {
            return (@as(u64, upper1) << 32) | lower;
        }
    }
}

pub fn setAlarm(target_ms: u64) void {
    reg(powman_timer_reg + atomic_clr).* = timer_alarm_enab;

    reg(powman_base + 0x78).* = powman_password | @as(u32, @as(u16, @truncate(target_ms >> 48)));
    reg(powman_base + 0x7C).* = powman_password | @as(u32, @as(u16, @truncate(target_ms >> 32)));
    reg(powman_base + 0x80).* = powman_password | @as(u32, @as(u16, @truncate(target_ms >> 16)));
    reg(powman_base + 0x84).* = powman_password | @as(u32, @as(u16, @truncate(target_ms)));

    // Clear any pending alarm: ALARM bit is W1C, so atomic_set writes 1 to clear it
    reg(powman_timer_reg + atomic_set).* = timer_alarm;

    reg(powman_timer_reg + atomic_set).* = timer_alarm_enab;
}

pub fn useXosc() void {
    reg(powman_timer_reg + atomic_set).* = timer_use_xosc;
    while ((reg(powman_timer_reg).* & timer_using_xosc) == 0) {}
}

pub fn useLposc() void {
    reg(powman_timer_reg + atomic_set).* = timer_use_lposc;
    while ((reg(powman_timer_reg).* & timer_using_lposc) == 0) {}
}

pub fn calibrateLposc() void {
    // Measure LPOSC frequency using the FC0 frequency counter (in CLOCKS block)
    // FC0 counts source clock edges over a reference period
    reg(clocks_base + 0x08C).* = 12000; // FC0_REF_KHZ = XOSC at 12 MHz
    reg(clocks_base + 0x090).* = 1; // FC0_MIN_KHZ
    reg(clocks_base + 0x094).* = 200; // FC0_MAX_KHZ

    // Select LPOSC as FC0 source (value 0x0E)
    reg(clocks_base + 0x0A0).* = 0x0E;

    // Wait for measurement to complete
    while ((reg(clocks_base + 0x0A4).* & (1 << 4)) == 0) {} // FC0_STATUS.DONE

    const result = reg(clocks_base + 0x0A8).*; // FC0_RESULT

    // FC0_RESULT: bits [29:5] = integer kHz, bits [4:0] = fractional (1/32 kHz)
    const freq_khz_int = (result >> 5) & 0x1FFF;
    const freq_khz_frac = (result & 0x1F) << 11; // Scale 5-bit fraction to 16-bit

    // Update POWMAN LPOSC frequency registers (with password)
    reg(powman_base + 0x50).* = powman_password | (freq_khz_int & 0x3F);
    reg(powman_base + 0x54).* = powman_password | (freq_khz_frac & 0xFFFF);

    // Disable FC0
    reg(clocks_base + 0x0A0).* = 0;
}

pub fn enterDormant() void {
    // Configure PWRUP0: enable AON timer alarm as wake source
    // PWRUP0 format: bit 0 = ENABLE, bits [5:1] = SOURCE (timer alarm)
    // Timer alarm source value is 0 in the SOURCE field
    reg(powman_base + 0x8C).* = powman_password | 0x01; // ENABLE, SOURCE=timer_alarm

    // Enable alarm interrupt so POWMAN can use it as wake source
    reg(powman_base + 0xE4).* = 1 << 1; // INTE: TIMER bit

    // Enter dormant by putting XOSC to sleep
    reg(xosc_base + 0x08).* = 0x636F6D61; // DORMANT = "coma"

    // Execution resumes here after wake
    // XOSC needs time to restabilize
    while ((reg(xosc_base + 0x04).* & (1 << 31)) == 0) {} // Wait STATUS.STABLE
}

pub fn softReset() noreturn {
    // ARM Cortex-M33 AIRCR: VECTKEY=0x05FA, SYSRESETREQ=bit 2
    const aircr: *volatile u32 = @ptrFromInt(0xE000ED0C);
    aircr.* = 0x05FA0004;
    while (true) {}
}
