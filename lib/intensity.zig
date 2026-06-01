/// Cubic distance falloff: fades a contribution from full intensity at
/// `normalized_distance` 0 to zero at 1, with `proximity³` shaping.
pub fn falloff(normalized_distance: f32) f32 {
    const proximity = 1 - normalized_distance;

    return proximity * proximity * proximity;
}
