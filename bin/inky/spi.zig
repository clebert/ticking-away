const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const IOCTL = linux.IOCTL;

// SPI ioctl commands (linux/spi/spidev.h, magic 'k')
const SPI_IOC_WR_MODE = IOCTL.IOW('k', 1, u8);
const SPI_IOC_WR_MAX_SPEED_HZ = IOCTL.IOW('k', 4, u32);

// GPIO ioctl commands (linux/gpio.h, magic 0xB4)
const GPIO_GET_LINEHANDLE_IOCTL = 0xC16CB403;
const GPIOHANDLE_GET_LINE_VALUES_IOCTL = 0xC040B408;
const GPIOHANDLE_SET_LINE_VALUES_IOCTL = 0xC040B409;

const GPIOHANDLE_REQUEST_INPUT = 0x1;
const GPIOHANDLE_REQUEST_OUTPUT = 0x2;
const GPIOHANDLE_REQUEST_BIAS_PULL_UP = 0x20;

// I2C ioctl commands (linux/i2c-dev.h)
const I2C_SLAVE = 0x0703;

// GPIO pin assignments (BCM numbering)
const pin_reset = 27;
const pin_busy = 17;
const pin_dc = 22;
const pin_cs0 = 26;
const pin_cs1 = 16;

const spi_speed_hz: u32 = 10_000_000;

pub const ChipSelect = enum { cs0, cs1, both };

const GpiohandleRequest = extern struct {
    lineoffsets: [64]u32 = .{0} ** 64,
    flags: u32 = 0,
    default_values: [64]u8 = .{0} ** 64,
    consumer_label: [32]u8 = .{0} ** 32,
    lines: u32 = 0,
    fd: i32 = -1,
};

const GpiohandleData = extern struct {
    values: [64]u8 = .{0} ** 64,
};

pub const Display = struct {
    spi_fd: posix.fd_t,
    gpio_chip_fd: posix.fd_t,
    reset_fd: posix.fd_t,
    busy_fd: posix.fd_t,
    dc_fd: posix.fd_t,
    cs0_fd: posix.fd_t,
    cs1_fd: posix.fd_t,

    pub fn init() !Display {
        const gpio_chip_fd = try posix.open("/dev/gpiochip0", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer posix.close(gpio_chip_fd);

        const reset_fd = try requestOutput(gpio_chip_fd, pin_reset, 1);
        errdefer posix.close(reset_fd);

        const busy_fd = try requestInput(gpio_chip_fd, pin_busy);
        errdefer posix.close(busy_fd);

        const dc_fd = try requestOutput(gpio_chip_fd, pin_dc, 0);
        errdefer posix.close(dc_fd);

        const cs0_fd = try requestOutput(gpio_chip_fd, pin_cs0, 1);
        errdefer posix.close(cs0_fd);

        const cs1_fd = try requestOutput(gpio_chip_fd, pin_cs1, 1);
        errdefer posix.close(cs1_fd);

        const spi_fd = try posix.open("/dev/spidev0.0", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer posix.close(spi_fd);

        try spiIoctl(spi_fd, SPI_IOC_WR_MODE, @as(u8, 0));
        try spiIoctl(spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, spi_speed_hz);

        var display = Display{
            .spi_fd = spi_fd,
            .gpio_chip_fd = gpio_chip_fd,
            .reset_fd = reset_fd,
            .busy_fd = busy_fd,
            .dc_fd = dc_fd,
            .cs0_fd = cs0_fd,
            .cs1_fd = cs1_fd,
        };

        try display.reset();
        try display.initSequence();

        return display;
    }

    pub fn deinit(self: *Display) void {
        posix.close(self.cs1_fd);
        posix.close(self.cs0_fd);
        posix.close(self.dc_fd);
        posix.close(self.busy_fd);
        posix.close(self.reset_fd);
        posix.close(self.gpio_chip_fd);
        posix.close(self.spi_fd);
    }

    pub fn beginData(self: *Display, cs: ChipSelect) !void {
        try self.sendCommand(0x10, cs, &.{});
        try setGpio(self.dc_fd, 1);
        try self.selectChip(cs);
    }

    pub fn writeData(self: *Display, data: []const u8) !void {
        try spiWrite(self.spi_fd, data);
    }

    pub fn endData(self: *Display) !void {
        try self.deselectChips();
        try setGpio(self.dc_fd, 0);
    }

    pub fn refresh(self: *Display) !void {
        std.debug.print("refresh: power on\n", .{});
        try self.sendCommand(0x04, .both, &.{});
        try self.busyWait(200);

        std.debug.print("refresh: triggering display update\n", .{});
        try self.sendCommand(0x12, .both, &.{0x00});
        try self.busyWait(32_000);

        std.debug.print("refresh: power off\n", .{});
        try self.sendCommand(0x02, .both, &.{0x00});
        try self.busyWait(200);

        std.debug.print("refresh: complete\n", .{});
    }

    fn reset(self: *Display) !void {
        std.debug.print("reset: asserting hardware reset\n", .{});
        try setGpio(self.reset_fd, 0);
        sleepMs(30);
        try setGpio(self.reset_fd, 1);
        sleepMs(30);
        try self.busyWait(300);

        const busy = try readGpio(self.busy_fd);

        if (busy == 1) {
            std.debug.print("reset: warning: BUSY still HIGH — display may not be connected\n", .{});
        } else {
            std.debug.print("reset: display responded (BUSY LOW)\n", .{});
        }
    }

    fn initSequence(self: *Display) !void {
        try self.sendCommand(0x74, .cs0, &.{ 0xC0, 0x1C, 0x1C, 0xCC, 0xCC, 0xCC, 0x15, 0x15, 0x55 });
        try self.sendCommand(0xF0, .both, &.{ 0x49, 0x55, 0x13, 0x5D, 0x05, 0x10 });
        try self.sendCommand(0x00, .both, &.{ 0xDF, 0x69 });
        try self.sendCommand(0x30, .both, &.{0x08});
        try self.sendCommand(0x50, .both, &.{0xF7});
        try self.sendCommand(0x60, .both, &.{ 0x03, 0x03 });
        try self.sendCommand(0x86, .both, &.{0x10});
        try self.sendCommand(0xE3, .both, &.{0x22});
        try self.sendCommand(0xE0, .both, &.{0x01});
        try self.sendCommand(0x61, .both, &.{ 0x04, 0xB0, 0x03, 0x20 });
        try self.sendCommand(0x01, .cs0, &.{ 0x0F, 0x00, 0x28, 0x2C, 0x28, 0x38 });
        try self.sendCommand(0xB6, .cs0, &.{0x07});
        try self.sendCommand(0x06, .cs0, &.{ 0xD8, 0x18 });
        try self.sendCommand(0xB7, .cs0, &.{0x01});
        try self.sendCommand(0x05, .cs0, &.{ 0xD8, 0x18 });
        try self.sendCommand(0xB0, .cs0, &.{0x01});
        try self.sendCommand(0xB1, .cs0, &.{0x02});

        std.debug.print("init: sequence complete\n", .{});
    }

    fn sendCommand(self: *Display, command: u8, cs: ChipSelect, data: []const u8) !void {
        try self.selectChip(cs);
        try setGpio(self.dc_fd, 0);
        sleepMs(300);
        try spiWrite(self.spi_fd, &.{command});

        if (data.len > 0) {
            try setGpio(self.dc_fd, 1);
            try spiWrite(self.spi_fd, data);
        }

        try self.deselectChips();
        try setGpio(self.dc_fd, 0);
    }

    fn busyWait(self: *Display, timeout_ms: u32) !void {
        if (try readGpio(self.busy_fd) == 1) {
            std.debug.print("  busy: HIGH at start, sleeping {d}ms (display may not be connected)\n", .{timeout_ms});
            sleepMs(timeout_ms);
            return;
        }

        var elapsed: u32 = 0;

        while (elapsed < timeout_ms) {
            if (try readGpio(self.busy_fd) == 0) {
                if (elapsed > 0) std.debug.print("  busy: ready after {d}ms\n", .{elapsed});
                return;
            }
            sleepMs(100);
            elapsed += 100;
        }

        std.debug.print("  busy: timeout after {d}ms\n", .{timeout_ms});
    }

    fn selectChip(self: *Display, cs: ChipSelect) !void {
        switch (cs) {
            .cs0 => {
                try setGpio(self.cs0_fd, 0);
                try setGpio(self.cs1_fd, 1);
            },
            .cs1 => {
                try setGpio(self.cs0_fd, 1);
                try setGpio(self.cs1_fd, 0);
            },
            .both => {
                try setGpio(self.cs0_fd, 0);
                try setGpio(self.cs1_fd, 0);
            },
        }
    }

    fn deselectChips(self: *Display) !void {
        try setGpio(self.cs0_fd, 1);
        try setGpio(self.cs1_fd, 1);
    }
};

pub fn probeEeprom() void {
    const fd = posix.open("/dev/i2c-1", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0) catch |err| {
        std.debug.print("eeprom: cannot open /dev/i2c-1: {s}\n", .{@errorName(err)});
        return;
    };

    defer posix.close(fd);

    const result = linux.ioctl(fd, I2C_SLAVE, 0x50);

    if (linux.E.init(result) != .SUCCESS) {
        std.debug.print("eeprom: cannot set I2C address 0x50\n", .{});
        return;
    }

    _ = posix.write(fd, &[_]u8{ 0x00, 0x00 }) catch |err| {
        std.debug.print("eeprom: write failed: {s}\n", .{@errorName(err)});
        return;
    };

    var buffer: [29]u8 = undefined;

    const n = posix.read(fd, &buffer) catch |err| {
        std.debug.print("eeprom: read failed: {s}\n", .{@errorName(err)});
        return;
    };

    if (n < 7) {
        std.debug.print("eeprom: short read ({d} bytes)\n", .{n});
        return;
    }

    const width = @as(u16, buffer[0]) | (@as(u16, buffer[1]) << 8);
    const height = @as(u16, buffer[2]) | (@as(u16, buffer[3]) << 8);
    const color_type = buffer[4];
    const display_variant = buffer[6];

    std.debug.print("eeprom: {d}x{d}, color={d}, variant={d}", .{ width, height, color_type, display_variant });

    if (display_variant == 21) {
        std.debug.print(" (Inky Impression 13.3\")\n", .{});
    } else {
        std.debug.print(" (warning: expected variant 21)\n", .{});
    }
}

fn requestOutput(chip_fd: posix.fd_t, pin: u32, default: u8) !posix.fd_t {
    var request = GpiohandleRequest{};

    request.lineoffsets[0] = pin;
    request.flags = GPIOHANDLE_REQUEST_OUTPUT;
    request.default_values[0] = default;
    request.lines = 1;
    @memcpy(request.consumer_label[0..4], "inky");

    try ioctl(chip_fd, GPIO_GET_LINEHANDLE_IOCTL, &request);

    return request.fd;
}

fn requestInput(chip_fd: posix.fd_t, pin: u32) !posix.fd_t {
    var request = GpiohandleRequest{};

    request.lineoffsets[0] = pin;
    request.flags = GPIOHANDLE_REQUEST_INPUT | GPIOHANDLE_REQUEST_BIAS_PULL_UP;
    request.lines = 1;
    @memcpy(request.consumer_label[0..4], "inky");

    try ioctl(chip_fd, GPIO_GET_LINEHANDLE_IOCTL, &request);

    return request.fd;
}

fn setGpio(line_fd: posix.fd_t, value: u8) !void {
    var data = GpiohandleData{};

    data.values[0] = value;

    try ioctl(line_fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &data);
}

fn readGpio(line_fd: posix.fd_t) !u8 {
    var data = GpiohandleData{};

    try ioctl(line_fd, GPIOHANDLE_GET_LINE_VALUES_IOCTL, &data);

    return data.values[0];
}

fn spiWrite(fd: posix.fd_t, data: []const u8) !void {
    var remaining = data;

    while (remaining.len > 0) {
        const written = posix.write(fd, remaining) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };

        remaining = remaining[written..];
    }
}

fn spiIoctl(fd: posix.fd_t, request: u32, value: anytype) !void {
    var v = value;

    try ioctl(fd, request, &v);
}

fn ioctl(fd: posix.fd_t, request: u32, arg: anytype) !void {
    const result = linux.ioctl(fd, request, @intFromPtr(arg));

    if (linux.E.init(result) != .SUCCESS) {
        return error.IoctlFailed;
    }
}

fn sleepMs(ms: u32) void {
    std.posix.nanosleep(0, @as(u64, ms) * 1_000_000);
}
