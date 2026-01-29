const testing = @import("std").testing;

const color = @import("../color/color.zig");

pub const Context = struct {
    buffer: []color.Color,
    width: usize,
    height: usize,
    y_offset: usize,
    total_height: usize,

    pub fn clear(self: *Context) void {
        @memset(self.buffer, color.black);
    }

    pub fn clearWithBackground(self: *Context, cx: f32, cy: f32, radius: f32) void {
        @setFloatMode(.optimized);
        const r2 = radius * radius;

        for (0..self.height) |local_y| {
            const global_y = self.globalY(local_y);
            const y: f32 = @floatFromInt(global_y);
            const dy = y - cy;
            const dy2 = dy * dy;

            for (0..self.width) |x| {
                const x_f: f32 = @floatFromInt(x);
                const dx = x_f - cx;
                const dist2 = dx * dx + dy2;

                self.pixel(x, local_y).* = if (dist2 <= r2) color.black else color.white;
            }
        }
    }

    inline fn pixel(self: *Context, x: usize, y: usize) *color.Color {
        return &self.buffer[y * self.width + x];
    }

    inline fn globalY(self: *const Context, local_y: usize) usize {
        return self.y_offset + local_y;
    }
};

test "clear sets all pixels to black" {
    var buffer: [16 * 16]color.Color = undefined;
    var ctx = Context{
        .buffer = &buffer,
        .width = 16,
        .height = 16,
        .y_offset = 0,
        .total_height = 16,
    };

    // Fill with white first
    @memset(&buffer, color.white);

    ctx.clear();

    // All should be black now
    for (buffer) |c| {
        try testing.expectApproxEqAbs(c[0], 0, 1e-6);
        try testing.expectApproxEqAbs(c[1], 0, 1e-6);
        try testing.expectApproxEqAbs(c[2], 0, 1e-6);
    }
}

test "clearWithBackground creates circle mask" {
    var buffer: [32 * 32]color.Color = undefined;
    var ctx = Context{
        .buffer = &buffer,
        .width = 32,
        .height = 32,
        .y_offset = 0,
        .total_height = 32,
    };

    const cx: f32 = 16;
    const cy: f32 = 16;
    const radius: f32 = 10;

    ctx.clearWithBackground(cx, cy, radius);

    // Center should be black
    const center_idx = 16 * 32 + 16;
    try testing.expectApproxEqAbs(buffer[center_idx][0], 0, 1e-6);

    // Corner should be white (outside circle)
    const corner_idx = 0;
    try testing.expectApproxEqAbs(buffer[corner_idx][0], 1, 1e-6);
}
