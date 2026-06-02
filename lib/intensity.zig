/// Cubic falloff: full intensity at normalized_distance 0, zero at 1.
pub fn falloff(normalized_distance: f32) f32 {
    const proximity = 1 - normalized_distance;

    return proximity * proximity * proximity;
}
