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
