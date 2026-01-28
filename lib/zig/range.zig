/// X-range for scanline intersection results
pub const Range = struct {
    x_min: f32,
    x_max: f32,

    // TODO: check if this is used at the end, otherwise remove
    pub fn intersect(self: Range, other: Range) ?Range {
        const result = Range{
            .x_min = @max(self.x_min, other.x_min),
            .x_max = @min(self.x_max, other.x_max),
        };
        return if (result.x_min <= result.x_max) result else null;
    }
};
