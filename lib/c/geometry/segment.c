#include "geometry/segment.h"
#include "fastmath.h"

// =================================================================================================
// Segment Initialization
// =================================================================================================

void segment_init(Segment *s, float x0, float y0, float x1, float y1) {
  s->x0 = x0;
  s->y0 = y0;
  s->x1 = x1;
  s->y1 = y1;
  s->dx = x1 - x0;
  s->dy = y1 - y0;
  s->len_sq = s->dx * s->dx + s->dy * s->dy;
  s->inv_len_sq = (s->len_sq > EPS_NORM) ? 1.0f / s->len_sq : 0.0f;
  s->len = (s->len_sq > EPS_NORM) ? sqrtf_impl(s->len_sq) : 0.0f;
  s->inv_len = (s->len > EPS_NORM) ? 1.0f / s->len : 0.0f;
}

// =================================================================================================
// Point-to-Segment Distance
// =================================================================================================

float segment_point_distance_sq(const Segment *s, float px, float py) {
  if (s->len_sq < EPS_NORM) {
    float fx = px - s->x0;
    float fy = py - s->y0;
    return fx * fx + fy * fy;
  }

  float fx = px - s->x0;
  float fy = py - s->y0;
  float t = (fx * s->dx + fy * s->dy) * s->inv_len_sq;

  t = clampf(t, 0.0f, 1.0f);

  float proj_x = s->x0 + t * s->dx;
  float proj_y = s->y0 + t * s->dy;
  float dist_x = px - proj_x;
  float dist_y = py - proj_y;

  return dist_x * dist_x + dist_y * dist_y;
}

float segment_point_distance_sq_with_t(const Segment *s, float px, float py, float *out_t) {
  if (s->len_sq < EPS_NORM) {
    float fx = px - s->x0;
    float fy = py - s->y0;
    *out_t = 0.0f;
    return fx * fx + fy * fy;
  }

  float fx = px - s->x0;
  float fy = py - s->y0;
  float t = (fx * s->dx + fy * s->dy) * s->inv_len_sq;

  t = clampf(t, 0.0f, 1.0f);
  *out_t = t;

  float proj_x = s->x0 + t * s->dx;
  float proj_y = s->y0 + t * s->dy;
  float dist_x = px - proj_x;
  float dist_y = py - proj_y;

  return dist_x * dist_x + dist_y * dist_y;
}

float point_to_segment_distance(float px, float py, float x0, float y0, float x1, float y1) {
  float dx = x1 - x0;
  float dy = y1 - y0;
  float len_sq = dx * dx + dy * dy;

  if (len_sq < EPS_NORM) {
    // Degenerate segment (point)
    float d = (px - x0) * (px - x0) + (py - y0) * (py - y0);
    return sqrtf_impl(d);
  }

  // Project point onto line, clamped to segment
  float t = clampf(((px - x0) * dx + (py - y0) * dy) / len_sq, 0.0f, 1.0f);

  float proj_x = x0 + t * dx;
  float proj_y = y0 + t * dy;

  float dist_x = px - proj_x;
  float dist_y = py - proj_y;
  return sqrtf_impl(dist_x * dist_x + dist_y * dist_y);
}

// =================================================================================================
// Capsule-Scanline Intersection
// =================================================================================================

int capsule_scanline_intersect(float y, const Segment *seg, float r, int *out_x_lo, int *out_x_hi) {
  float x_min = 1e9f, x_max = -1e9f;
  int has_intersection = 0;
  float r_sq = r * r;

  // 1. Start cap: circle at (x0, y0)
  float dy0 = y - seg->y0;
  if (dy0 * dy0 < r_sq) {
    float dx = sqrtf_impl(r_sq - dy0 * dy0);
    float lo = seg->x0 - dx, hi = seg->x0 + dx;
    if (lo < x_min)
      x_min = lo;
    if (hi > x_max)
      x_max = hi;
    has_intersection = 1;
  }

  // 2. End cap: circle at (x1, y1)
  float dy1 = y - seg->y1;
  if (dy1 * dy1 < r_sq) {
    float dx = sqrtf_impl(r_sq - dy1 * dy1);
    float lo = seg->x1 - dx, hi = seg->x1 + dx;
    if (lo < x_min)
      x_min = lo;
    if (hi > x_max)
      x_max = hi;
    has_intersection = 1;
  }

  // 3. Rectangle body: slab around line segment (uses precomputed len/inv_len)
  if (seg->len_sq > EPS_NORM) {
    // Unit perpendicular (normal to segment) using precomputed inv_len
    float nx = -seg->dy * seg->inv_len;

    // Check if this y is within the slab's perpendicular extent
    // Perpendicular distance from point (x, y) to infinite line through (x0,y0) with direction (dx,
    // dy) For a horizontal slice at y, we need to find where |perp_dist| <= r

    // The perpendicular distance at any point (x, y) is: nx*(x - x0) + ny*(y - y0)
    // We want |nx*(x - x0) + ny*(y - y0)| <= r
    // Solving for x: x = x0 + (+-r - ny*(y - y0)) / nx  (when nx != 0)

    if (nx * nx > EPS_NORM) { // nx != 0, line is not horizontal
      float ny = seg->dx * seg->inv_len;
      float base = ny * (y - seg->y0);

      // Two x values where perpendicular distance = +-r
      float x_at_plus_r = seg->x0 + (r - base) / nx;
      float x_at_minus_r = seg->x0 + (-r - base) / nx;

      float slab_lo = x_at_plus_r < x_at_minus_r ? x_at_plus_r : x_at_minus_r;
      float slab_hi = x_at_plus_r > x_at_minus_r ? x_at_plus_r : x_at_minus_r;

      // Clamp to segment extent by projecting onto segment direction
      // We need the portion where t = projection onto segment is in [0, 1]
      // t = ((x - x0) * dx + (y - y0) * dy) / len_sq

      // For x = slab_lo: compute t
      float t_lo = ((slab_lo - seg->x0) * seg->dx + (y - seg->y0) * seg->dy) * seg->inv_len_sq;
      float t_hi = ((slab_hi - seg->x0) * seg->dx + (y - seg->y0) * seg->dy) * seg->inv_len_sq;

      // Ensure t_lo <= t_hi for overlap check (don't swap slab bounds - they're already sorted)
      if (t_lo > t_hi) {
        float tmp = t_lo;
        t_lo = t_hi;
        t_hi = tmp;
      }

      // Only include if segment overlaps [0, 1]
      if (t_hi >= 0.0f && t_lo <= 1.0f) {
        // Use the computed slab bounds (the endpoint caps will handle edge cases)
        if (slab_lo < x_min)
          x_min = slab_lo;
        if (slab_hi > x_max)
          x_max = slab_hi;
        has_intersection = 1;
      }
    } else {
      // nx ~= 0, line is nearly horizontal
      // Check if y is within r of the line's y-range
      float y_lo = seg->y0 < seg->y1 ? seg->y0 : seg->y1;
      float y_hi = seg->y0 > seg->y1 ? seg->y0 : seg->y1;

      if (y >= y_lo - r && y <= y_hi + r) {
        // Perpendicular distance is just |y - line_y|, which varies along segment
        // For horizontal segments, the slab spans x0 to x1 with width r on each side
        float slab_lo = (seg->x0 < seg->x1 ? seg->x0 : seg->x1) - r;
        float slab_hi = (seg->x0 > seg->x1 ? seg->x0 : seg->x1) + r;
        if (slab_lo < x_min)
          x_min = slab_lo;
        if (slab_hi > x_max)
          x_max = slab_hi;
        has_intersection = 1;
      }
    }
  }

  if (!has_intersection)
    return 0;

  *out_x_lo = (int)x_min;     // floor
  *out_x_hi = (int)x_max + 1; // ceil
  return 1;
}
