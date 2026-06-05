// Bare-metal "HELLO WORLD" for the TRMNL OG (Espressif ESP32-C3, RV32IMC),
// drawing onto its 7.5" 800x480 UC8179 e-ink panel with bit-banged SPI. No
// ESP-IDF, no Arduino, no libraries — a RAM-resident image flashed raw to flash
// offset 0x0 with espflash (save-image then write-bin), which the ROM first-stage
// loader copies into SRAM and runs with no second-stage bootloader.
//
// Panel GPIOs from usetrmnl/trmnl-firmware src/DEV_Config.h (BOARD_TRMNL); the
// panel is powered straight off 3V3, so there is no rail-enable pin to drive.
// Register addresses and the watchdog unlock keys are from the ESP32-C3 TRM /
// esp-idf soc headers; the panel command bytes from the bb_epaper library the
// stock firmware uses (chip family UC81xx, panel EP75_800x480).

const sck: u5 = 7;
const mosi: u5 = 8;
const cs: u5 = 6;
const rst: u5 = 10;
const dc: u5 = 5;
const busy: u5 = 4;

const width = 800;
const height = 480;
var framebuffer: [width * height / 8]u8 = undefined;

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

    // UC8179 power-on + init (bb_epaper epd75_init_sequence_full).
    command(0x01, &[_]u8{ 0x07, 0x07, 0x3F, 0x3F }); // PWR
    command(0x04, &[_]u8{}); // PON
    waitReady();
    command(0x00, &[_]u8{0x1F}); // PSR: internal LUT, black/white
    command(0x61, &[_]u8{ 0x03, 0x20, 0x01, 0xE0 }); // TRES: 800x480
    command(0x15, &[_]u8{0x00}); // DUSPI: single SPI
    command(0x50, &[_]u8{ 0x21, 0x07 }); // CDI
    command(0x60, &[_]u8{0x22}); // TCON

    for (&framebuffer) |*byte| byte.* = 0xFF; // bit = 1 is white
    drawMessage();

    // Old plane all-white, new plane the rendered image, then refresh.
    plane(0x10, null); // DTM1
    plane(0x13, &framebuffer); // DTM2
    command(0x12, &[_]u8{}); // DRF: display refresh
    waitReady();

    while (true) {}
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
    // UC8179 busy line is active-low (low = busy); bounded so a mis-wire cannot wedge.
    var spins: u32 = 0;
    while (spins < 50_000_000) : (spins += 1) {
        if (mmio(0x6000403C).* & (@as(u32, 1) << busy) != 0) return; // GPIO_IN
    }
}

fn delayMs(milliseconds: u32) void {
    var spins: u32 = 0;
    // Coarse busy-wait at the ~40 MHz ROM boot clock (no PLL configured); callers
    // only need the panel's reset-pulse minimums, so running long is harmless.
    const loops = milliseconds * 50_000;
    while (spins < loops) : (spins += 1) asm volatile ("" ::: .{ .memory = true });
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
    // SPI mode 0, MSB first: data set while the clock is low, sampled on the rising edge.
    var bits = value;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if (bits & 0x80 != 0) high(mosi) else low(mosi);
        high(sck);
        low(sck);
        bits <<= 1;
    }
}

fn command(opcode: u8, data: []const u8) void {
    low(cs);
    low(dc);
    spiByte(opcode);
    high(dc);
    for (data) |byte| spiByte(byte);
    high(cs);
}

fn plane(opcode: u8, maybe_data: ?*const [framebuffer.len]u8) void {
    low(cs);
    low(dc);
    spiByte(opcode);
    high(dc);
    var index: usize = 0;
    while (index < framebuffer.len) : (index += 1) {
        spiByte(if (maybe_data) |data| data[index] else 0xFF);
    }
    high(cs);
}

// Classic 5x7 font, one byte per column with bit 0 the top row. Only the glyphs
// that appear in "HELLO WORLD" are defined.
const font = [_][5]u8{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00 }, // space
    .{ 0x7F, 0x08, 0x08, 0x08, 0x7F }, // H
    .{ 0x7F, 0x49, 0x49, 0x49, 0x41 }, // E
    .{ 0x7F, 0x40, 0x40, 0x40, 0x40 }, // L
    .{ 0x3E, 0x41, 0x41, 0x41, 0x3E }, // O
    .{ 0x7F, 0x20, 0x18, 0x20, 0x7F }, // W
    .{ 0x7F, 0x09, 0x19, 0x29, 0x46 }, // R
    .{ 0x7F, 0x41, 0x41, 0x41, 0x3E }, // D
};
const message = [_]u8{ 1, 2, 3, 3, 4, 0, 5, 4, 6, 3, 7 };
const scale = 10;

fn drawMessage() void {
    const advance = 6 * scale;
    const text_width = message.len * advance - scale;
    const x0 = (width - text_width) / 2;
    const y0 = (height - 7 * scale) / 2;
    for (message, 0..) |glyph, glyph_index| {
        const gx = x0 + glyph_index * advance;
        for (font[glyph], 0..) |column, column_index| {
            for (0..7) |row| {
                if (((column >> @as(u3, @intCast(row))) & 1) != 0) {
                    fillBlock(gx + column_index * scale, y0 + row * scale);
                }
            }
        }
    }
}

fn fillBlock(x: usize, y: usize) void {
    for (0..scale) |dy| {
        for (0..scale) |dx| setBlack(x + dx, y + dy);
    }
}

fn setBlack(x: usize, y: usize) void {
    if (x >= width or y >= height) return;
    framebuffer[y * (width / 8) + (x >> 3)] &= ~(@as(u8, 0x80) >> @as(u3, @intCast(x & 7)));
}
