const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const IOCTL = linux.IOCTL;

// SPI ioctl commands (linux/spi/spidev.h, magic 'k')
const SPI_IOC_WR_MODE = IOCTL.IOW('k', 1, u8);
const SPI_IOC_WR_MAX_SPEED_HZ = IOCTL.IOW('k', 4, u32);

// GPIO ioctl commands (linux/gpio.h, magic 0xB4)
const GPIO_GET_LINEHANDLE_IOCTL = 0xC16CB403;
const GPIOHANDLE_SET_LINE_VALUES_IOCTL = 0xC040B409;

const GPIOHANDLE_REQUEST_OUTPUT = 0x2;

// GPIO pin assignments (BCM numbering)
const pin_reset = 27;
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
    dc_fd: posix.fd_t,
    cs0_fd: posix.fd_t,
    cs1_fd: posix.fd_t,

    pub fn init() !Display {
        const gpio_chip_fd = try posix.open("/dev/gpiochip0", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer posix.close(gpio_chip_fd);

        const reset_fd = try requestOutput(gpio_chip_fd, pin_reset, 1);
        errdefer posix.close(reset_fd);

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
        posix.close(self.reset_fd);
        posix.close(self.gpio_chip_fd);
        posix.close(self.spi_fd);
    }

    pub fn beginData(self: *Display, cs: ChipSelect) !void {
        try self.sendCommand(0x10, cs, &.{});
        sleepMs(300);
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
        try self.sendCommand(0x04, .both, &.{});
        sleepMs(500); // 300ms command processing + 200ms for boost converter after PON
        try self.sendCommand(0x12, .both, &.{0x00});
        sleepMs(300);
        try self.sendCommand(0x02, .both, &.{0x00});
        sleepMs(300);
    }

    fn reset(self: *Display) !void {
        try setGpio(self.reset_fd, 0);
        sleepMs(30); // Hold low for controller to register reset
        try setGpio(self.reset_fd, 1);
        sleepMs(30); // Wait for controller to come out of reset
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
    }

    fn sendCommand(self: *Display, command: u8, cs: ChipSelect, data: []const u8) !void {
        try self.selectChip(cs);
        try setGpio(self.dc_fd, 0);
        try spiWrite(self.spi_fd, &.{command});

        if (data.len > 0) {
            try setGpio(self.dc_fd, 1);
            try spiWrite(self.spi_fd, data);
        }

        try self.deselectChips();
        try setGpio(self.dc_fd, 0);
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

fn setGpio(line_fd: posix.fd_t, value: u8) !void {
    var data = GpiohandleData{};

    data.values[0] = value;

    try ioctl(line_fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &data);
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
    std.posix.nanosleep(ms / 1000, @as(u64, ms % 1000) * 1_000_000);
}
