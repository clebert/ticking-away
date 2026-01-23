#pragma once

#include "geometry.h"

// =================================================================================================
// Falloff Computation
// =================================================================================================

// Exponential falloff constant: -3 / ln(2) for exp(-3*t) = exp2(EXP_NEG3_FACTOR * t)
#define EXP_NEG3_FACTOR -4.328085f

// Compute falloff value for glow effects
// falloff_type: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// t: normalized distance (0 at center, 1 at edge)
static inline float compute_falloff(int falloff_type, float t) {
  float one_minus_t = 1.0f - t;
  switch (falloff_type) {
    case 0: return one_minus_t;
    case 1: return one_minus_t * one_minus_t;
    case 2: return one_minus_t * one_minus_t * one_minus_t;
    case 3: return fast_exp2f(EXP_NEG3_FACTOR * t) * one_minus_t;
    default: return one_minus_t * one_minus_t;
  }
}

// =================================================================================================
// Pixel Operations (Linear Color Space)
// =================================================================================================

// Additive blending for float framebuffer (linear space).
// r, g, b are in 0.0-1.0 range, a is alpha multiplier (0.0-1.0).
static inline void set_pixel_additive_f(
  float* fb, int width, int height,
  int x, int y, float r, float g, float b, float a
) {
  if (x < 0 || x >= width || y < 0 || y >= height) return;

  int idx = (y * width + x) * 4;
  fb[idx] += r * a;
  fb[idx + 1] += g * a;
  fb[idx + 2] += b * a;
  // Alpha channel not modified (assumed pre-initialized to 1.0)
}

// Alpha blending for float framebuffer (linear space).
// r, g, b are in 0.0-1.0 range, a is alpha (0.0-1.0).
static inline void set_pixel_alpha_f(
  float* fb, int width, int height,
  int x, int y, float r, float g, float b, float a
) {
  if (x < 0 || x >= width || y < 0 || y >= height) return;

  int idx = (y * width + x) * 4;
  float inv_a = 1.0f - a;
  fb[idx] = r * a + fb[idx] * inv_a;
  fb[idx + 1] = g * a + fb[idx + 1] * inv_a;
  fb[idx + 2] = b * a + fb[idx + 2] * inv_a;
  fb[idx + 3] = 1.0f;
}

// =================================================================================================
// Line Drawing with Glow (Distance Field, Additive Blending, Linear Color Space)
// =================================================================================================

// Draw a line with glow effect using distance field approach and additive blending.
// Designed for light rays where drawing multiple overlapping rays (e.g., per-band)
// accumulates to correct brightness.
// r, g, b are in 0.0-1.0 range (linear color space)
static void draw_line_with_glow_additive_f(
  float* fb, int width, int height,
  float x0, float y0, float x1, float y1,
  float r, float g, float b,
  float glow_width,
  float intensity,
  int falloff,
  const float* clip_triangle,
  const float* clip_circle,
  const float* exclude_triangle
) {
  SegmentParams seg;
  init_segment_params(&seg, x0, y0, x1, y1);
  float glow_width_sq = glow_width * glow_width;

  float min_y = (y0 < y1 ? y0 : y1) - glow_width;
  float max_y = (y0 > y1 ? y0 : y1) + glow_width;

  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (y_start < 0) y_start = 0;
  if (y_end > height) y_end = height;

  for (int y = y_start; y < y_end; y++) {
    float py = (float)y + 0.5f;

    int x_lo, x_hi;
    if (!capsule_scanline_intersect(py, &seg, glow_width, &x_lo, &x_hi)) {
      continue;
    }

    if (x_lo < 0) x_lo = 0;
    if (x_hi > width) x_hi = width;

    for (int x = x_lo; x < x_hi; x++) {
      float px = (float)x + 0.5f;

      if (clip_triangle && !point_in_triangle(px, py,
          clip_triangle[0], clip_triangle[1],
          clip_triangle[2], clip_triangle[3],
          clip_triangle[4], clip_triangle[5])) {
        continue;
      }

      if (clip_circle) {
        float dx = px - clip_circle[0];
        float dy = py - clip_circle[1];
        if (dx * dx + dy * dy > clip_circle[2] * clip_circle[2]) {
          continue;
        }
      }

      if (exclude_triangle && point_in_triangle(px, py,
          exclude_triangle[0], exclude_triangle[1],
          exclude_triangle[2], exclude_triangle[3],
          exclude_triangle[4], exclude_triangle[5])) {
        continue;
      }

      float dist_sq = point_to_segment_distance_sq(&seg, px, py);
      if (dist_sq >= glow_width_sq) continue;

      float dist = sqrtf_impl(dist_sq);
      float t = dist / glow_width;
      float falloff_value = compute_falloff(falloff, t);

      float alpha = falloff_value * intensity;
      set_pixel_additive_f(fb, width, height, x, y, r, g, b, alpha);
    }
  }
}
