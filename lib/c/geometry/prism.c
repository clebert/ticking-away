#include "geometry/prism.h"
#include "fastmath.h"
#include <stddef.h>

// =================================================================================================
// Prism Creation
// =================================================================================================

void prism_create(float cx, float cy, float size, float apex_angle_deg, Prism *out) {
  // Clamp to avoid degenerate triangles (tan_half -> 0 or cos_half -> 0)
  apex_angle_deg = clampf(apex_angle_deg, 1.0f, 179.0f);
  float half_apex_rad = (apex_angle_deg / 2.0f) * PI / 180.0f;
  float cos_half = cosf_approx(half_apex_rad);
  if (fabsf_impl(cos_half) < EPS_NORM)
    cos_half = EPS_NORM;
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
// Prism Queries
// =================================================================================================

float prism_scale(const Prism *prism) {
  float total = 0.0f;
  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float ex = prism->vertices[(size_t)j * 2] - prism->vertices[(size_t)i * 2];
    float ey = prism->vertices[(size_t)j * 2 + 1] - prism->vertices[(size_t)i * 2 + 1];
    total += sqrtf_impl(ex * ex + ey * ey);
  }
  return total / 3.0f;
}

void prism_get_vertex(const Prism *prism, int idx, float *out_x, float *out_y) {
  if (idx < 0 || idx > 2) {
    *out_x = 0.0f;
    *out_y = 0.0f;
    return;
  }
  *out_x = prism->vertices[(size_t)idx * 2];
  *out_y = prism->vertices[(size_t)idx * 2 + 1];
}

void prism_get_edge(const Prism *prism, int edge_idx, float *out_ax, float *out_ay, float *out_bx,
                    float *out_by) {
  if (edge_idx < 0 || edge_idx > 2) {
    *out_ax = *out_ay = *out_bx = *out_by = 0.0f;
    return;
  }
  int i = edge_idx;
  int j = (i + 1) % 3;
  *out_ax = prism->vertices[(size_t)i * 2];
  *out_ay = prism->vertices[(size_t)i * 2 + 1];
  *out_bx = prism->vertices[(size_t)j * 2];
  *out_by = prism->vertices[(size_t)j * 2 + 1];
}

// =================================================================================================
// Point-in-Triangle Test
// =================================================================================================

int point_in_triangle(float px, float py, float x0, float y0, float x1, float y1, float x2,
                      float y2) {
  float denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
  if (denom > -EPS_NORM && denom < EPS_NORM)
    return 0;

  float a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denom;
  float b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denom;
  float c = 1.0f - a - b;

  return (a >= 0.0f && b >= 0.0f && c >= 0.0f);
}

int prism_contains_point(const Prism *prism, float px, float py) {
  return point_in_triangle(px, py, prism->vertices[0], prism->vertices[1], prism->vertices[2],
                           prism->vertices[3], prism->vertices[4], prism->vertices[5]);
}
