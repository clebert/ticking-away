const color_space = @import("color_space.zig");

pub const Range = struct {
    x_min: f32,
    x_max: f32,
};

pub const Context = struct {
    linear_colors: []color_space.Linear,
    width: usize,
    height: usize,
    y_offset: usize,
    total_height: usize,

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

                self.pixel(x, local_y).* = if (dist2 <= r2) color_space.Linear.black else color_space.Linear.white;
            }
        }
    }

    inline fn pixel(self: *Context, x: usize, y: usize) *color_space.Linear {
        return &self.linear_colors[y * self.width + x];
    }

    inline fn globalY(self: *const Context, local_y: usize) usize {
        return self.y_offset + local_y;
    }
};
