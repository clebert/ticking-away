pub const Falloff = enum {
    linear,
    quadratic,
    cubic,
    exponential,

    pub fn apply(self: Falloff, normalized_distance: f32) f32 {
        const proximity = 1 - normalized_distance;

        return switch (self) {
            .linear => proximity,
            .quadratic => proximity * proximity,
            .cubic => proximity * proximity * proximity,
            .exponential => @exp(-3 * normalized_distance) * proximity,
        };
    }
};

pub const Attenuation = struct {
    normalized_distance: f32,
    falloff: Falloff,
};
