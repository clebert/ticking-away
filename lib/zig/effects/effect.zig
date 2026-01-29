const color = @import("../color/color.zig");

/// Effect function signature for buffer post-processing.
pub const ApplyFn = *const fn (buffer: []color.Color, width: usize, height: usize, context: *anyopaque) void;

/// Effect descriptor for pipeline registration.
pub const Effect = struct {
    name: []const u8,
    apply: ApplyFn,
};

/// Fixed-size effect pipeline (max 8 effects).
pub const Pipeline = struct {
    effects: [max_effects]?EffectEntry = [_]?EffectEntry{null} ** max_effects,
    count: usize = 0,

    pub const max_effects: usize = 8;

    const EffectEntry = struct {
        apply: ApplyFn,
        context: *anyopaque,
    };

    /// Add an effect to the pipeline.
    pub fn add(self: *Pipeline, effect: ApplyFn, context: *anyopaque) bool {
        if (self.count >= max_effects) return false;
        self.effects[self.count] = .{ .apply = effect, .context = context };
        self.count += 1;
        return true;
    }

    /// Execute all effects in order.
    pub fn execute(self: *const Pipeline, buffer: []color.Color, width: usize, height: usize) void {
        for (self.effects[0..self.count]) |entry| {
            if (entry) |e| {
                e.apply(buffer, width, height, e.context);
            }
        }
    }

    /// Clear all effects.
    pub fn clear(self: *Pipeline) void {
        for (&self.effects) |*e| {
            e.* = null;
        }
        self.count = 0;
    }
};
