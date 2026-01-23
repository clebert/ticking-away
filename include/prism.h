#pragma once

#include "fastmath.h"

// =================================================================================================
// Prism Geometry (Simplified - no optical properties)
// =================================================================================================

typedef struct {
  float vertices[6];  // 3 vertices x 2 coords
} Prism;

// Compute characteristic length of prism (average edge length).
// Used for scale-aware epsilon calculations.
static inline float prism_scale(const Prism* prism) {
  float total = 0.0f;
  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float ex = prism->vertices[j * 2] - prism->vertices[i * 2];
    float ey = prism->vertices[j * 2 + 1] - prism->vertices[i * 2 + 1];
    total += sqrtf_impl(ex * ex + ey * ey);
  }
  return total / 3.0f;
}

// Create an isosceles triangle prism with apex at top, centered at (cx, cy).
// apex_angle_deg: angle at the apex (top vertex)
// size: width of the base
static void create_prism(
  float cx, float cy, float size,
  float apex_angle_deg,
  Prism* out
) {
  // Clamp to avoid degenerate triangles (tan_half → 0 or cos_half → 0)
  apex_angle_deg = clampf(apex_angle_deg, 1.0f, 179.0f);
  float half_apex_rad = (apex_angle_deg / 2.0f) * PI / 180.0f;
  float cos_half = cosf_approx(half_apex_rad);
  if (fabsf_impl(cos_half) < EPS_NORM) cos_half = EPS_NORM;
  float tan_half = sinf_approx(half_apex_rad) / cos_half;
  float h = (size / 2.0f) / tan_half;

  float apex_offset = (2.0f * h) / 3.0f;
  float base_offset = h / 3.0f;

  // v0 = apex (top), v1 = bottom-right, v2 = bottom-left
  out->vertices[0] = cx;
  out->vertices[1] = cy - apex_offset;
  out->vertices[2] = cx + size / 2.0f;
  out->vertices[3] = cy + base_offset;
  out->vertices[4] = cx - size / 2.0f;
  out->vertices[5] = cy + base_offset;
}

// =================================================================================================
// Ray-Segment Intersection
// =================================================================================================

typedef struct {
  int hit;
  float t;        // Parameter along ray
  float u;        // Parameter along edge (0=start vertex, 1=end vertex), -1 if not set
  int edge_idx;   // Which edge was hit (0, 1, 2 for prism), -1 if not set
  float px, py;   // Hit point
} RayHit;

// Intersect ray (ox, oy) + t*(dx, dy) with line segment (ax, ay)-(bx, by).
// Returns hit info if intersection found with t > eps_t.
// eps_u: tolerance for segment parameter (typically 1e-5f for robustness)
static RayHit ray_segment_intersect(
  float ox, float oy, float dx, float dy,
  float ax, float ay, float bx, float by,
  float eps_t, float eps_u
) {
  RayHit result = {0, 0.0f, -1.0f, -1, 0.0f, 0.0f};

  float ex = bx - ax;
  float ey = by - ay;

  // Ray perpendicular
  float perp_x = -dy;
  float perp_y = dx;

  float denom = ex * perp_x + ey * perp_y;

  // Scale-aware parallel check: compare denom against product of vector magnitudes
  float edge_len = sqrtf_impl(ex * ex + ey * ey);
  float dir_len = sqrtf_impl(dx * dx + dy * dy);
  float eps_denom = EPS_PARALLEL * edge_len * dir_len;
  if (eps_denom < EPS_NORM) eps_denom = EPS_NORM;
  if (fabsf_impl(denom) < eps_denom) return result;  // Parallel

  float vx = ox - ax;
  float vy = oy - ay;

  float t = (ex * vy - ey * vx) / denom;
  if (t < eps_t) return result;  // Behind ray origin

  float u = (vx * perp_x + vy * perp_y) / denom;
  // Use tolerance to avoid missing vertex hits due to floating-point noise
  if (u < -eps_u || u > 1.0f + eps_u) return result;  // Outside segment
  u = clampf(u, 0.0f, 1.0f);

  result.hit = 1;
  result.t = t;
  result.u = u;  // Store parametric position along edge
  // Compute hit point from clamped u to ensure it lies exactly on segment
  result.px = ax + ex * u;
  result.py = ay + ey * u;
  return result;
}

// Find where a ray from (ox, oy) in direction (dx, dy) first enters the prism.
// Returns hit info with the entry point, edge index, and parametric position along edge.
static RayHit find_prism_entry(
  float ox, float oy, float dx, float dy,
  const Prism* prism
) {
  RayHit best = {0, T_MAX, -1.0f, -1, 0.0f, 0.0f};

  // Scale-aware epsilons based on prism size
  float scale = prism_scale(prism);
  float eps_t = EPS_REL * scale;  // t tolerance in world units
  float eps_u = EPS_REL;          // u tolerance (segment parameter, dimensionless)

  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float ax = prism->vertices[i * 2];
    float ay = prism->vertices[i * 2 + 1];
    float bx = prism->vertices[j * 2];
    float by = prism->vertices[j * 2 + 1];

    RayHit hit = ray_segment_intersect(ox, oy, dx, dy, ax, ay, bx, by, eps_t, eps_u);
    if (hit.hit && hit.t < best.t) {
      best = hit;
      best.edge_idx = i;  // Store which edge was hit
    }
  }

  return best;
}

// Find where a ray from center in direction (angle) exits the prism.
// This is used for the exit rays that appear to originate from center.
static RayHit find_prism_exit_from_center(
  float cx, float cy, float angle,
  const Prism* prism
) {
  float dx = cosf_approx(angle);
  float dy = sinf_approx(angle);

  // From center (inside triangle), there's exactly one forward boundary hit.
  // Take the farthest t for stability in degenerate cases (vertex ties / tiny noise).
  RayHit best = {0, 0.0f, -1.0f, -1, 0.0f, 0.0f};

  // Scale-aware epsilons based on prism size
  float scale = prism_scale(prism);
  float eps_t = EPS_REL * scale;
  float eps_u = EPS_REL;

  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float ax = prism->vertices[i * 2];
    float ay = prism->vertices[i * 2 + 1];
    float bx = prism->vertices[j * 2];
    float by = prism->vertices[j * 2 + 1];

    RayHit hit = ray_segment_intersect(cx, cy, dx, dy, ax, ay, bx, by, eps_t, eps_u);
    if (hit.hit && hit.t > best.t) {
      best = hit;
      best.edge_idx = i;
    }
  }

  return best;
}
