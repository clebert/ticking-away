// Bare-metal watchface for the TRMNL OG (Espressif ESP32-C3, RV32IMC), drawing
// the Dark-Side-of-the-Moon prism onto its 7.5" 800x480 UC8179 e-ink panel in
// four greyscale levels with bit-banged SPI. No ESP-IDF, no Arduino, no
// libraries — a RAM-resident image flashed raw to flash offset 0x0 with espflash
// (save-image then write-bin), which the ROM first-stage loader copies into SRAM
// and runs with no second-stage bootloader.
//
// The shared `lib` render core rasterises the watchface band-by-band; dither_trmnl
// reduces each pixel to one of {0, 85, 170, 255}, and packBand splits that into the
// two 1-bit planes the UC8179 combines into 4 greys.
//
// Panel GPIOs from usetrmnl/trmnl-firmware src/DEV_Config.h (BOARD_TRMNL); the
// panel is powered straight off 3V3, so there is no rail-enable pin to drive.
// Register addresses and the watchdog unlock keys are from the ESP32-C3 TRM /
// esp-idf soc headers; the 4-gray init, waveform LUTs, and per-level plane bits are
// from the GoodDisplay GDEY075T7 demo (via GxEPD2_4G): a host-loaded custom waveform
// (PSR 0x3F, LUTs into 0x20-0x25), because this panel's OTP carries no 4-gray waveform.
// The CPU is taken from the ~40 MHz ROM boot clock to 160 MHz (BBPLL via REGI2C)
// following esp-idf rtc_clk.c so the software-float render finishes in seconds.

const std = @import("std");

const lib = @import("lib");

// Freestanding: a render fault just leaves the panel untouched; trap instead of
// pulling formatting/abort into the image.
pub const panic = std.debug.FullPanic(struct {
    fn handler(_: []const u8, _: ?usize) noreturn {
        @trap();
    }
}.handler);

const sck: u5 = 7;
const mosi: u5 = 8;
const cs: u5 = 6;
const rst: u5 = 10;
const dc: u5 = 5;
const busy: u5 = 4;

const width = 800;
const height = 480;
const plane_bytes = width * height / 8;
const band_height = 1;

// Calibration: draw the four solid levels as equal vertical bars (black .. white, left
// to right) instead of the watchface, to photograph the panel and measure each shade's
// real reflectance. Set false for the watchface.
const calibrate = false;

const config = lib.Config{
    .background_enabled = false,
    .prism_normalized_size = 0.9,
    .prism_glow_linear_green = 0.75,
    .prism_glow_normalized_width = 0.07,
    .rainbow_normalized_spread = 0.5,
    .hand_glow_normalized_width = 0.02,
    .rainbow_palette_id = .oklch_balanced,
    .texture = .dither_trmnl,
    .grain_normalized_deviation = 0.1,
    // No supersampling: with software floats it would quadruple the render time, and
    // the Floyd–Steinberg dither already hides the aliased edges on the panel.
    .supersample_enabled = false,
};

// Derived from config so linear_buffer's size always matches the factor renderBand uses.
const supersample = lib.frame.supersampleFactor(config);

const image = lib.Image.init(width, height);

// One UC8179 RAM plane each: plane0 -> command 0x10 (DTM1), plane1 -> 0x13 (DTM2).
// The (plane0, plane1) bit pair indexes the custom LUTs; a set bit is the white side.
var plane0: [plane_bytes]u8 = undefined;
var plane1: [plane_bytes]u8 = undefined;

// Frame-scoped render scratch reused across bands. linear_buffer holds the linear
// strip, srgb_buffer the dithered grey one, dither_error_buffer the Floyd–Steinberg
// row errors (zeroed by renderBand on band_index 0).
var linear_buffer: [width * band_height * supersample * supersample]lib.Linear = undefined;
var srgb_buffer: [width * band_height]lib.Srgb = undefined;
var dither_error_buffer: [lib.dither_trmnl.errorBufferSize(width)]f32 = undefined;

// GDEY075T7 4-gray waveform LUTs (GoodDisplay demo, via GxEPD2_4G), loaded into the
// UC8179's LUT registers. Each is 7 phase-groups of 6 bytes; the (old,new) plane pair
// routes a pixel to LUTKK/WK/KW/WW for black/dark/light/white.
const lut_vcom = [_]u8{
    0x00, 0x0A, 0x00, 0x00, 0x00, 0x01,
    0x60, 0x14, 0x14, 0x00, 0x00, 0x01,
    0x00, 0x14, 0x0A, 0x00, 0x00, 0x01,
    0x00, 0x13, 0x0A, 0x01, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
const lut_ww = [_]u8{
    0x40, 0x0A, 0x00, 0x00, 0x00, 0x01,
    0x90, 0x14, 0x14, 0x00, 0x00, 0x01,
    0x10, 0x14, 0x0A, 0x00, 0x00, 0x01,
    0xA0, 0x13, 0x0A, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
const lut_kw = [_]u8{
    0x40, 0x0A, 0x00, 0x00, 0x00, 0x01,
    0x90, 0x14, 0x14, 0x00, 0x00, 0x01,
    0x00, 0x14, 0x0A, 0x00, 0x00, 0x01,
    0x99, 0x0C, 0x01, 0x03, 0x04, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
const lut_wk = [_]u8{
    0x40, 0x0A, 0x00, 0x00, 0x00, 0x01,
    0x90, 0x14, 0x14, 0x00, 0x00, 0x01,
    0x00, 0x14, 0x0A, 0x00, 0x00, 0x01,
    0x99, 0x0B, 0x04, 0x04, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
const lut_kk = [_]u8{
    0x80, 0x0A, 0x00, 0x00, 0x00, 0x01,
    0x90, 0x14, 0x14, 0x00, 0x00, 0x01,
    0x20, 0x14, 0x0A, 0x00, 0x00, 0x01,
    0x50, 0x13, 0x01, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
const lut_bd = lut_ww; // border reuses the white waveform

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\.option push
        \\.option norelax
        \\la gp, __global_pointer$
        \\.option pop
        \\la sp, __stack_top
        \\call zigMain
        \\1: j 1b
    );
}

export fn zigMain() noreturn {
    disableWatchdogs();
    setCpuClock160();

    for ([_]u5{ sck, mosi, cs, rst, dc }) |pin| configOutput(pin);
    configInput(busy);
    high(cs);
    low(sck);

    high(rst);
    delayMs(200);
    low(rst);
    delayMs(10);
    high(rst);
    delayMs(200);

    // UC8179 4-gray power-on + init (GoodDisplay GDEY075T7 demo via GxEPD2_4G): load the
    // custom waveform from the host (PSR 0x3F) since the panel OTP has no 4-gray LUT.
    command(0x00, &[_]u8{0x1F}); // PSR (interim; KW mode)
    command(0x01, &[_]u8{ 0x07, 0x07, 0x3F, 0x3F, 0x09 }); // PWR: DC-DC on, gate/source rails
    command(0x06, &[_]u8{ 0x17, 0x17, 0x28, 0x17 }); // BTST: booster soft start
    command(0x61, &[_]u8{ 0x03, 0x20, 0x01, 0xE0 }); // TRES: 800x480
    command(0x15, &[_]u8{0x00}); // DUSPI: single SPI
    command(0x50, &[_]u8{ 0x29, 0x07 }); // CDI (interim)
    command(0x60, &[_]u8{0x22}); // TCON
    command(0xE3, &[_]u8{0x22}); // PWS: power saving
    command(0x00, &[_]u8{0x3F}); // PSR: 4-gray waveform LUT from registers
    command(0x50, &[_]u8{ 0x31, 0x07 }); // CDI: 4-gray border path
    command(0x82, &[_]u8{0x30}); // VDCS: VCOM_DC
    command(0x20, &lut_vcom);
    command(0x21, &lut_ww); // white
    command(0x22, &lut_kw); // light grey
    command(0x23, &lut_wk); // dark grey
    command(0x24, &lut_kk); // black
    command(0x25, &lut_bd); // border
    command(0x04, &[_]u8{}); // PON
    delayMs(100);
    waitReady();

    if (calibrate) drawCalibrationBars() else renderWatchface();

    plane(0x10, &plane0); // DTM1
    plane(0x13, &plane1); // DTM2
    command(0x12, &[_]u8{}); // DRF: display refresh
    delayMs(100);
    waitReady();

    while (true) {}
}

fn renderWatchface() void {
    @memset(&plane0, 0);
    @memset(&plane1, 0);

    const time = lib.Time.init(7, 14.0);

    for (0..height / band_height) |band_index| {
        const band = lib.frame.renderBand(
            config,
            time,
            image,
            band_height,
            band_index,
            &linear_buffer,
            &srgb_buffer,
            &dither_error_buffer,
        ) catch return;

        packBand(band);
    }
}

fn drawCalibrationBars() void {
    @memset(&plane0, 0);
    @memset(&plane1, 0);

    for (0..height) |y| {
        const row = y * (width / 8);

        for (0..width) |x| {
            const level = x * 4 / width; // four equal bars: 0 black .. 3 white

            emitLevel(row, x, @intCast(level));
        }
    }
}

// Writes column `x` of the plane row at byte offset `row` as one of the four levels
// (grey >> 6, 0 = black .. 3 = white): a clean binary code where plane0 (DTM1) is the
// high bit, plane1 (DTM2) the low bit, a set bit the white side. If the two mid greys
// come out swapped on hardware, exchange the plane0/plane1 conditions; black and white
// are fixed.
inline fn emitLevel(row: usize, x: usize, level: u8) void {
    const mask = @as(u8, 0x80) >> @as(u3, @intCast(x & 7));
    const byte_index = row + (x >> 3);

    if (level & 0b10 != 0) plane0[byte_index] |= mask;
    if (level & 0b01 != 0) plane1[byte_index] |= mask;
}

// Splits the dithered grey strip into the two RAM planes.
fn packBand(band: lib.Image.Band(lib.Srgb)) void {
    for (0..band.bandHeight()) |y| {
        const row = band.imageY(y) * (width / 8);

        for (0..width) |x| {
            emitLevel(row, x, band.colorAt(x, y).r >> 6);
        }
    }
}

inline fn mmio(comptime address: usize) *volatile u32 {
    return @ptrFromInt(address);
}

inline fn high(pin: u5) void {
    mmio(0x60004008).* = @as(u32, 1) << pin; // GPIO_OUT_W1TS
}

inline fn low(pin: u5) void {
    mmio(0x6000400C).* = @as(u32, 1) << pin; // GPIO_OUT_W1TC
}

inline fn ioMux(pin: u5) *volatile u32 {
    return @ptrFromInt(0x60009004 + @as(usize, pin) * 4);
}

fn configOutput(pin: u5) void {
    ioMux(pin).* = 1 << 12; // MCU_SEL = 1: plain GPIO function
    mmio(0x60004024).* = @as(u32, 1) << pin; // GPIO_ENABLE_W1TS
}

fn configInput(pin: u5) void {
    ioMux(pin).* = (1 << 12) | (1 << 9); // GPIO function + FUN_IE input buffer
    mmio(0x60004028).* = @as(u32, 1) << pin; // GPIO_ENABLE_W1TC
}

fn waitReady() void {
    // UC8179 busy line is active-low (low = busy). The bound is a mis-wire backstop
    // sized for ~5 s at 160 MHz so it never trips during a multi-second 4-gray refresh.
    var spins: u32 = 0;
    while (spins < 200_000_000) : (spins += 1) {
        if (mmio(0x6000403C).* & (@as(u32, 1) << busy) != 0) return; // GPIO_IN
    }
}

fn delayMs(milliseconds: u32) void {
    var spins: u32 = 0;
    // Coarse busy-wait calibrated for the 160 MHz CPU clock; callers only need the
    // panel's reset-pulse minimums, so running long is harmless.
    const loops = milliseconds * 200_000;
    while (spins < loops) : (spins += 1) asm volatile ("" ::: .{ .memory = true });
}

// ESP32-C3 mask-ROM REGI2C helpers (esp32c3.rom.ld); the analog BBPLL registers
// are only reachable through this internal-I2C bridge. The first helper writes a whole
// 8-bit analog register; the mask helper splices a bit-field.
const rom_i2c_write_reg: *const fn (
    block: u32,
    host_id: u32,
    register_address: u32,
    data: u32,
) callconv(.c) void = @ptrFromInt(0x4000195C);

const rom_i2c_write_reg_mask: *const fn (
    block: u32,
    host_id: u32,
    register_address: u32,
    most_significant_bit: u32,
    least_significant_bit: u32,
    data: u32,
) callconv(.c) void = @ptrFromInt(0x40001960);

// Bring the BBPLL up to 480 MHz and run the CPU off its /3 tap (160 MHz). Sequence
// and analog constants are from esp-idf rtc_clk.c / clk_tree_ll.h (esp32c3), cross-
// checked against esp-hal; it is idempotent whether or not the ROM left the PLL on.
fn setCpuClock160() void {
    // Open the REGI2C path to the BBPLL (clear ANA_I2C_BBPLL_M, bit 17).
    mmio(0x6000E044).* &= ~(@as(u32, 1) << 17);

    // Power the BBPLL: clear BB_I2C_FORCE_PD (6) | BBPLL_I2C_FORCE_PD (8) | BBPLL_FORCE_PD (10).
    mmio(0x60008000).* &= ~((@as(u32, 1) << 6) | (@as(u32, 1) << 8) | (@as(u32, 1) << 10));

    // Select the 480 MHz PLL (SYSTEM_PLL_FREQ_SEL, bit 2).
    mmio(0x600C0008).* |= @as(u32, 1) << 2;

    // Arm BBPLL self-calibration (STOP_FORCE_HIGH = 0, STOP_FORCE_LOW = 1).
    mmio(0x6000E040).* &= ~(@as(u32, 1) << 2);
    mmio(0x6000E040).* |= @as(u32, 1) << 3;

    // 40 MHz XTAL -> 480 MHz analog config, REGI2C block 0x66 (I2C_BBPLL), host 0.
    rom_i2c_write_reg(0x66, 0, 4, 0x6B); // MODE_HF
    rom_i2c_write_reg(0x66, 0, 2, 0x50); // OC_REF_DIV: (dchgp<<4)|div_ref
    rom_i2c_write_reg(0x66, 0, 3, 0x08); // OC_DIV_7_0
    rom_i2c_write_reg_mask(0x66, 0, 5, 2, 0, 0); // OC_DR1
    rom_i2c_write_reg_mask(0x66, 0, 5, 6, 4, 0); // OC_DR3
    rom_i2c_write_reg(0x66, 0, 6, 0x93); // OC_DCUR: (2<<6)|(1<<4)|dcur
    rom_i2c_write_reg_mask(0x66, 0, 9, 1, 0, 2); // OC_VCO_DBIAS
    rom_i2c_write_reg_mask(0x66, 0, 6, 5, 4, 2); // OC_DHREF_SEL
    rom_i2c_write_reg_mask(0x66, 0, 6, 7, 6, 1); // OC_DLREF_SEL

    // Let the PLL lock before the CPU is switched onto it.
    var settle: u32 = 0;
    while (settle < 4000) : (settle += 1) asm volatile ("" ::: .{ .memory = true });

    // CPUPERIOD_SEL = 1 selects the 480/3 = 160 MHz tap (preserves PLL_FREQ_SEL, bit 2).
    mmio(0x600C0008).* = (mmio(0x600C0008).* & ~@as(u32, 0x3)) | 1;
    // PRE_DIV_CNT (9:0) = 0 and SOC_CLK_SEL (11:10) = 1 (PLL).
    mmio(0x600C0058).* = (mmio(0x600C0058).* & ~((@as(u32, 0x3) << 10) | 0x3FF)) | (@as(u32, 1) << 10);
}

fn disableWatchdogs() void {
    // RTC WDT: unlock (key 0x50D83AA1), clear config, re-lock.
    mmio(0x600080A8).* = 0x50D83AA1;
    mmio(0x60008090).* = 0;
    mmio(0x600080A8).* = 0;
    // Super WDT: unlock (key 0x8F1D312A), set SWD_DISABLE (bit 30), re-lock.
    mmio(0x600080B0).* = 0x8F1D312A;
    mmio(0x600080AC).* |= @as(u32, 1) << 30;
    mmio(0x600080B0).* = 0;
    // Timer-group-0 WDT: unlock (key 0x50D83AA1), clear config, re-lock.
    mmio(0x6001F064).* = 0x50D83AA1;
    mmio(0x6001F048).* = 0;
    mmio(0x6001F064).* = 0;
}

fn spiByte(value: u8) void {
    // SPI mode 0, MSB first: data set while the clock is low, sampled on the rising
    // edge. spiDelay holds each half-cycle so the bit-banged SCK stays a few MHz —
    // within the panel's limit — instead of tracking the 160 MHz core clock.
    var bits = value;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if (bits & 0x80 != 0) high(mosi) else low(mosi);
        spiDelay();
        high(sck);
        spiDelay();
        low(sck);
        bits <<= 1;
    }
}

inline fn spiDelay() void {
    var spins: u32 = 0;
    while (spins < 8) : (spins += 1) asm volatile ("" ::: .{ .memory = true });
}

fn command(opcode: u8, data: []const u8) void {
    low(cs);
    low(dc);
    spiByte(opcode);
    high(dc);
    for (data) |byte| spiByte(byte);
    high(cs);
}

fn plane(opcode: u8, data: *const [plane_bytes]u8) void {
    low(cs);
    low(dc);
    spiByte(opcode);
    high(dc);
    for (data) |byte| spiByte(byte);
    high(cs);
}
