#pragma once

#include "fastmath.h"

// =================================================================================================
// Geometry Primitives
// =================================================================================================
//
// Generic computational geometry functions for 2D operations:
// - Point-to-segment distance calculations
// - Point-in-triangle testing
// - Ray-circle intersection
// - Segment-circle clipping
// - Capsule-scanline intersection

// =================================================================================================
// Segment Parameters (precomputed for efficiency)
// =================================================================================================

// Precomputed segment data (compute once per line, outside pixel loop)
typedef struct {
  float x0, y0;
  float x1, y1;
  float dx, dy;
  float len_sq;
  float inv_len_sq;
  float len;      // sqrt(len_sq), precomputed for capsule intersection
  float inv_len;  // 1/len, precomputed for capsule intersection
} SegmentParams;

static inline void init_segment_params(SegmentParams* s, float x0, float y0, float x1, float y1) {
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

// Returns squared distance from point to segment (no sqrt)
static inline float point_to_segment_distance_sq(const SegmentParams* s, float px, float py) {
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

// Compute distance from point (px, py) to line segment (x0, y0)-(x1, y1)
static float point_to_segment_distance(
  float px, float py,
  float x0, float y0, float x1, float y1
) {
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
// Point-in-Triangle Test
// =================================================================================================

// Check if point is inside triangle using barycentric coordinates
static int point_in_triangle(
  float px, float py,
  float x0, float y0,
  float x1, float y1,
  float x2, float y2
) {
  float denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
  if (denom > -EPS_NORM && denom < EPS_NORM) return 0;

  float a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denom;
  float b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denom;
  float c = 1.0f - a - b;

  return (a >= 0.0f && b >= 0.0f && c >= 0.0f);
}

// =================================================================================================
// Ray-Circle Intersection
// =================================================================================================

// Find intersection of ray with circle. Returns 1 if hit, 0 if miss.
// Ray starts at (ox, oy) with direction (dx, dy) (not necessarily normalized).
// Circle centered at (cx, cy) with given radius.
// Output: intersection point stored in out_x, out_y.
static int ray_circle_intersection(
  float ox, float oy, float dx, float dy,
  float cx, float cy, float radius,
  float* out_x, float* out_y
) {
  float len = sqrtf_impl(dx * dx + dy * dy);
  if (len <= EPS_NORM) return 0;
  float inv_len = 1.0f / len;
  dx *= inv_len;
  dy *= inv_len;

  float fx = ox - cx;
  float fy = oy - cy;

  float b = 2.0f * (fx * dx + fy * dy);
  float c = fx * fx + fy * fy - radius * radius;
  float discriminant = b * b - 4.0f * c;

  // Clamp tiny negative discriminants to 0 (floating-point noise near tangent)
  float eps_disc = EPS_REL * radius * radius;
  if (discriminant < 0.0f) {
    if (discriminant > -eps_disc) {
      discriminant = 0.0f;
    } else {
      return 0;
    }
  }

  float sqrt_disc = sqrtf_impl(discriminant);
  float t1 = (-b + sqrt_disc) * 0.5f;
  float t2 = (-b - sqrt_disc) * 0.5f;

  // Scale-aware epsilon for self-intersection rejection
  float eps_t = EPS_REL * radius;
  float t;
  if (t2 > eps_t) {
    t = t2;
  } else if (t1 > eps_t) {
    t = t1;
  } else {
    return 0;
  }

  *out_x = ox + dx * t;
  *out_y = oy + dy * t;
  return 1;
}

// =================================================================================================
// Capsule-Scanline Intersection
// =================================================================================================

// Compute x-interval where capsule intersects a horizontal scanline.
// Returns 0 if no intersection, 1 if intersection found.
// The capsule is defined by precomputed segment params with radius r (glow width).
// Uses precomputed len/inv_len to avoid sqrt per scanline.
//
// Algorithm: A capsule is the Minkowski sum of a line segment and a disk.
// We decompose it into three regions and compute their intersection with y:
//   1. Start cap: circle at segment start (x0, y0)
//   2. End cap: circle at segment end (x1, y1)
//   3. Rectangle body: slab of width 2r around the segment
// The final x-interval is the union of all intersecting regions.
static int capsule_scanline_intersect(
  float y, const SegmentParams* seg, float r,
  int* out_x_lo, int* out_x_hi
) {
  float x_min = 1e9f, x_max = -1e9f;
  int has_intersection = 0;
  float r_sq = r * r;

  // 1. Start cap: circle at (x0, y0)
  float dy0 = y - seg->y0;
  if (dy0 * dy0 < r_sq) {
    float dx = sqrtf_impl(r_sq - dy0 * dy0);
    float lo = seg->x0 - dx, hi = seg->x0 + dx;
    if (lo < x_min) x_min = lo;
    if (hi > x_max) x_max = hi;
    has_intersection = 1;
  }

  // 2. End cap: circle at (x1, y1)
  float dy1 = y - seg->y1;
  if (dy1 * dy1 < r_sq) {
    float dx = sqrtf_impl(r_sq - dy1 * dy1);
    float lo = seg->x1 - dx, hi = seg->x1 + dx;
    if (lo < x_min) x_min = lo;
    if (hi > x_max) x_max = hi;
    has_intersection = 1;
  }

  // 3. Rectangle body: slab around line segment (uses precomputed len/inv_len)
  if (seg->len_sq > EPS_NORM) {
    // Unit perpendicular (normal to segment) using precomputed inv_len
    float nx = -seg->dy * seg->inv_len;
    float ny = seg->dx * seg->inv_len;

    // Check if this y is within the slab's perpendicular extent
    // Perpendicular distance from point (x, y) to infinite line through (x0,y0) with direction (dx, dy)
    // For a horizontal slice at y, we need to find where |perp_dist| <= r

    // The perpendicular distance at any point (x, y) is: nx*(x - x0) + ny*(y - y0)
    // We want |nx*(x - x0) + ny*(y - y0)| <= r
    // Solving for x: x = x0 + (±r - ny*(y - y0)) / nx  (when nx != 0)

    if (nx * nx > EPS_NORM) {  // nx != 0, line is not horizontal
      float base = ny * (y - seg->y0);

      // Two x values where perpendicular distance = ±r
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
        float tmp = t_lo; t_lo = t_hi; t_hi = tmp;
      }

      // Only include if segment overlaps [0, 1]
      if (t_hi >= 0.0f && t_lo <= 1.0f) {
        // Use the computed slab bounds (the endpoint caps will handle edge cases)
        if (slab_lo < x_min) x_min = slab_lo;
        if (slab_hi > x_max) x_max = slab_hi;
        has_intersection = 1;
      }
    } else {
      // nx ≈ 0, line is nearly horizontal
      // Check if y is within r of the line's y-range
      float y_lo = seg->y0 < seg->y1 ? seg->y0 : seg->y1;
      float y_hi = seg->y0 > seg->y1 ? seg->y0 : seg->y1;

      if (y >= y_lo - r && y <= y_hi + r) {
        // Perpendicular distance is just |y - line_y|, which varies along segment
        // For horizontal segments, the slab spans x0 to x1 with width r on each side
        float slab_lo = (seg->x0 < seg->x1 ? seg->x0 : seg->x1) - r;
        float slab_hi = (seg->x0 > seg->x1 ? seg->x0 : seg->x1) + r;
        if (slab_lo < x_min) x_min = slab_lo;
        if (slab_hi > x_max) x_max = slab_hi;
        has_intersection = 1;
      }
    }
  }

  if (!has_intersection) return 0;

  *out_x_lo = (int)x_min;  // floor
  *out_x_hi = (int)x_max + 1;  // ceil
  return 1;
}

// =================================================================================================
// Segment-Circle Clipping
// =================================================================================================

// Clip a line segment to the interior of a circle.
// Returns 1 if any portion of the segment is inside, 0 if entirely outside.
// Output: clipped segment endpoints stored in out_x0, out_y0, out_x1, out_y1.
static int clip_segment_to_circle(
  float x0, float y0, float x1, float y1,
  float cx, float cy, float radius,
  float* out_x0, float* out_y0, float* out_x1, float* out_y1
) {
  float d0sq = (x0 - cx) * (x0 - cx) + (y0 - cy) * (y0 - cy);
  float d1sq = (x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy);
  float rsq = radius * radius;
  float tolerance = radius * 0.01f;
  float rsq_tol = (radius + tolerance) * (radius + tolerance);
  int p0_inside = d0sq <= rsq_tol;
  int p1_inside = d1sq <= rsq_tol;

  if (p0_inside && p1_inside) {
    *out_x0 = x0; *out_y0 = y0;
    *out_x1 = x1; *out_y1 = y1;
    return 1;
  }

  float dx = x1 - x0;
  float dy = y1 - y0;
  float fx = x0 - cx;
  float fy = y0 - cy;

  float a = dx * dx + dy * dy;
  float b = 2.0f * (fx * dx + fy * dy);
  float c = fx * fx + fy * fy - rsq;

  if (a < EPS_NORM) return 0;

  float discriminant = b * b - 4.0f * a * c;
  if (discriminant < 0.0f) {
    return 0;
  }

  float sqrt_disc = sqrtf_impl(discriminant);
  float t1 = (-b - sqrt_disc) / (2.0f * a);
  float t2 = (-b + sqrt_disc) / (2.0f * a);

  float t_start = 0.0f;
  float t_end = 1.0f;

  if (p0_inside && !p1_inside) {
    if (t2 > 0.0f && t2 <= 1.0f) {
      t_end = t2;
    } else {
      return 0;
    }
  } else if (!p0_inside && p1_inside) {
    if (t1 >= 0.0f && t1 < 1.0f) {
      t_start = t1;
    } else {
      return 0;
    }
  } else {
    if (t1 > 1.0f || t2 < 0.0f) {
      return 0;
    }
    t_start = t1 > 0.0f ? t1 : 0.0f;
    t_end = t2 < 1.0f ? t2 : 1.0f;
  }

  if (t_start >= t_end) return 0;

  *out_x0 = x0 + t_start * dx;
  *out_y0 = y0 + t_start * dy;
  *out_x1 = x0 + t_end * dx;
  *out_y1 = y0 + t_end * dy;
  return 1;
}
