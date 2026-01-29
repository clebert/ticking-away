#include "geometry/intersect.h"
#include "fastmath.h"
#include "geometry/prism.h"

// =================================================================================================
// Ray-Segment Intersection
// =================================================================================================

RayHit ray_segment_intersect(float ox, float oy, float dx, float dy, float ax, float ay, float bx,
                             float by, float eps_t, float eps_u) {
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
  if (eps_denom < EPS_NORM)
    eps_denom = EPS_NORM;
  if (fabsf_impl(denom) < eps_denom)
    return result; // Parallel

  float vx = ox - ax;
  float vy = oy - ay;

  float t = (ex * vy - ey * vx) / denom;
  if (t < eps_t)
    return result; // Behind ray origin

  float u = (vx * perp_x + vy * perp_y) / denom;
  // Use tolerance to avoid missing vertex hits due to floating-point noise
  if (u < -eps_u || u > 1.0f + eps_u)
    return result; // Outside segment
  u = clampf(u, 0.0f, 1.0f);

  result.hit = 1;
  result.t = t;
  result.u = u; // Store parametric position along edge
  // Compute hit point from clamped u to ensure it lies exactly on segment
  result.px = ax + ex * u;
  result.py = ay + ey * u;
  return result;
}

// =================================================================================================
// Ray-Prism Intersection
// =================================================================================================

RayHit prism_find_entry(float ox, float oy, float dx, float dy, const Prism *prism) {
  RayHit best = {0, T_MAX, -1.0f, -1, 0.0f, 0.0f};

  // Scale-aware epsilons based on prism size
  float scale = prism_scale(prism);
  float eps_t = EPS_REL * scale; // t tolerance in world units
  float eps_u = EPS_REL;         // u tolerance (segment parameter, dimensionless)

  for (int i = 0; i < 3; i++) {
    float ax, ay, bx, by;
    prism_get_edge(prism, i, &ax, &ay, &bx, &by);

    RayHit hit = ray_segment_intersect(ox, oy, dx, dy, ax, ay, bx, by, eps_t, eps_u);
    if (hit.hit && hit.t < best.t) {
      best = hit;
      best.edge_idx = i; // Store which edge was hit
    }
  }

  return best;
}

RayHit prism_find_exit_from_center(float cx, float cy, float angle, const Prism *prism) {
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
    float ax, ay, bx, by;
    prism_get_edge(prism, i, &ax, &ay, &bx, &by);

    RayHit hit = ray_segment_intersect(cx, cy, dx, dy, ax, ay, bx, by, eps_t, eps_u);
    if (hit.hit && hit.t > best.t) {
      best = hit;
      best.edge_idx = i;
    }
  }

  return best;
}

// =================================================================================================
// Ray-Circle Intersection
// =================================================================================================

int ray_circle_intersect(float ox, float oy, float dx, float dy, float cx, float cy, float radius,
                         float *out_x, float *out_y) {
  float len = sqrtf_impl(dx * dx + dy * dy);
  if (len <= EPS_NORM)
    return 0;
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
// Segment-Circle Clipping
// =================================================================================================

int clip_segment_to_circle(float x0, float y0, float x1, float y1, float cx, float cy, float radius,
                           float *out_x0, float *out_y0, float *out_x1, float *out_y1) {
  float d0sq = (x0 - cx) * (x0 - cx) + (y0 - cy) * (y0 - cy);
  float d1sq = (x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy);
  float rsq = radius * radius;
  float tolerance = radius * 0.01f;
  float rsq_tol = (radius + tolerance) * (radius + tolerance);
  int p0_inside = d0sq <= rsq_tol;
  int p1_inside = d1sq <= rsq_tol;

  if (p0_inside && p1_inside) {
    *out_x0 = x0;
    *out_y0 = y0;
    *out_x1 = x1;
    *out_y1 = y1;
    return 1;
  }

  float dx = x1 - x0;
  float dy = y1 - y0;
  float fx = x0 - cx;
  float fy = y0 - cy;

  float a = dx * dx + dy * dy;
  float b = 2.0f * (fx * dx + fy * dy);
  float c_coef = fx * fx + fy * fy - rsq;

  if (a < EPS_NORM)
    return 0;

  float discriminant = b * b - 4.0f * a * c_coef;
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

  if (t_start >= t_end)
    return 0;

  *out_x0 = x0 + t_start * dx;
  *out_y0 = y0 + t_start * dy;
  *out_x1 = x0 + t_end * dx;
  *out_y1 = y0 + t_end * dy;
  return 1;
}
