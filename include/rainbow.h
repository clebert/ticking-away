#pragma once

#include "color.h"
#include "geometry.h"
#include "math.h"
#include "palette.h"
#include "prism.h"

// =================================================================================================
// Rainbow Gradient Rendering
// =================================================================================================

// Gradient mode: determines pixel inclusion and iteration bounds
typedef enum {
  GRADIENT_EXTERNAL,  // Inside circle, outside prism (rainbow fan)
  GRADIENT_INTERNAL   // Inside prism only
} GradientMode;

// Interpolate between rainbow bands based on t (0-1)
// Uses OkLab color space for perceptually uniform gradients.
// Returns smoothly interpolated color between the 7 discrete bands.
// Extrapolates beyond visible spectrum: t<0 toward infrared, t>1 toward ultraviolet.
static RGB_Linear interpolate_rainbow_color(float t) {
  // Handle extrapolation beyond visible spectrum
  if (t < 0.0f) {
    // Extrapolate toward infrared (darker, deeper red)
    // Infrared: sRGB(140, 0, 0) -> dark red beyond visible
    OkLab lab_infrared = linear_to_oklab(
      srgb_to_linear(140.0f / 255.0f),
      srgb_to_linear(0.0f),
      srgb_to_linear(0.0f)
    );
    OkLab lab_red = BAND_COLORS_OKLAB[0];

    // t=0 is red, t=-1 would be pure infrared
    float frac = -t;  // 0 at red, 1 at t=-1
    frac = clampf(frac, 0.0f, 1.0f);

    OkLab lab_interp;
    lab_interp.L = lab_red.L + frac * (lab_infrared.L - lab_red.L);
    lab_interp.a = lab_red.a + frac * (lab_infrared.a - lab_red.a);
    lab_interp.b = lab_red.b + frac * (lab_infrared.b - lab_red.b);
    return oklab_to_linear(lab_interp);
  }

  if (t > 1.0f) {
    // Extrapolate toward ultraviolet (deeper magenta/purple)
    // Ultraviolet: sRGB(80, 0, 120) -> deep purple beyond visible
    OkLab lab_ultraviolet = linear_to_oklab(
      srgb_to_linear(80.0f / 255.0f),
      srgb_to_linear(0.0f),
      srgb_to_linear(120.0f / 255.0f)
    );
    OkLab lab_violet = BAND_COLORS_OKLAB[NUM_BANDS - 1];

    // t=1 is violet, t=2 would be pure ultraviolet
    float frac = t - 1.0f;  // 0 at violet, 1 at t=2
    frac = clampf(frac, 0.0f, 1.0f);

    OkLab lab_interp;
    lab_interp.L = lab_violet.L + frac * (lab_ultraviolet.L - lab_violet.L);
    lab_interp.a = lab_violet.a + frac * (lab_ultraviolet.a - lab_violet.a);
    lab_interp.b = lab_violet.b + frac * (lab_ultraviolet.b - lab_violet.b);
    return oklab_to_linear(lab_interp);
  }

  // Map t to band index: t=0 -> band 0 (red), t=1 -> band 6 (violet)
  float scaled = t * (float)(NUM_BANDS - 1);
  int band_lo = (int)scaled;
  int band_hi = band_lo + 1;

  // Clamp to valid range
  if (band_hi >= NUM_BANDS) band_hi = NUM_BANDS - 1;

  // Interpolation factor within the band
  float frac = scaled - (float)band_lo;

  // Interpolate in OkLab space for perceptually uniform gradients
  OkLab lab_lo = BAND_COLORS_OKLAB[band_lo];
  OkLab lab_hi = BAND_COLORS_OKLAB[band_hi];

  OkLab lab_interp;
  lab_interp.L = lab_lo.L + frac * (lab_hi.L - lab_lo.L);
  lab_interp.a = lab_lo.a + frac * (lab_hi.a - lab_lo.a);
  lab_interp.b = lab_lo.b + frac * (lab_hi.b - lab_lo.b);

  // Convert back to linear RGB
  return oklab_to_linear(lab_interp);
}

// Draw continuous gradient fill with band-based color interpolation (linear color space)
static void draw_gradient_continuous_f(
  float* fb, int width, int height,
  GradientMode mode,
  float origin_x, float origin_y,
  float cx, float cy, float radius,
  float angle_start, float angle_end,
  const Prism* prism,
  float intensity,
  int reverse_spectrum
) {
  float a1 = angle_start;
  float a2 = angle_end;
  while (a1 < 0) a1 += 2.0f * PI;
  while (a1 >= 2.0f * PI) a1 -= 2.0f * PI;
  while (a2 < 0) a2 += 2.0f * PI;
  while (a2 >= 2.0f * PI) a2 -= 2.0f * PI;

  float angle_diff = a2 - a1;
  if (angle_diff > PI) angle_diff -= 2.0f * PI;
  if (angle_diff < -PI) angle_diff += 2.0f * PI;

  float angle_span = angle_diff > 0 ? angle_diff : -angle_diff;

  if (angle_span < 0.001f || angle_span > PI) return;

  int reverse = (angle_diff < 0);
  if (reverse) {
    float tmp = a1; a1 = a2; a2 = tmp;
  }

  // Save original boundary angles for interpolation (before epsilon expansion)
  float a1_orig = a1;

  // Determine wrap-around based on original geometry (before epsilon expansion).
  // After the reverse swap above, a1→a2 is the CCW arc we want to fill.
  // If a1 > a2, that arc crosses the 0/2π boundary.
  int wrap_around = (a1 > a2);

  // Expand acceptance range by epsilon to ensure boundary pixels are included
  float eps = 0.002f;
  a1 -= eps;
  a2 += eps;
  if (a1 < 0) a1 += 2.0f * PI;
  if (a2 >= 2.0f * PI) a2 -= 2.0f * PI;

  int x_start = 0, x_end = width, y_start = 0, y_end = height;
  float radius_sq = radius * radius;

  if (mode == GRADIENT_INTERNAL) {
    float v0x = prism->vertices[0], v0y = prism->vertices[1];
    float v1x = prism->vertices[2], v1y = prism->vertices[3];
    float v2x = prism->vertices[4], v2y = prism->vertices[5];

    float min_x = v0x < v1x ? (v0x < v2x ? v0x : v2x) : (v1x < v2x ? v1x : v2x);
    float max_x = v0x > v1x ? (v0x > v2x ? v0x : v2x) : (v1x > v2x ? v1x : v2x);
    float min_y = v0y < v1y ? (v0y < v2y ? v0y : v2y) : (v1y < v2y ? v1y : v2y);
    float max_y = v0y > v1y ? (v0y > v2y ? v0y : v2y) : (v1y > v2y ? v1y : v2y);

    x_start = (int)min_x;
    x_end = (int)max_x + 1;
    y_start = (int)min_y;
    y_end = (int)max_y + 1;

    if (x_start < 0) x_start = 0;
    if (y_start < 0) y_start = 0;
    if (x_end > width) x_end = width;
    if (y_end > height) y_end = height;
  }

  for (int y = y_start; y < y_end; y++) {
    float py = (float)y + 0.5f;
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;

      if (mode == GRADIENT_EXTERNAL) {
        float dx_circle = px - cx;
        float dy_circle = py - cy;
        if (dx_circle * dx_circle + dy_circle * dy_circle > radius_sq) continue;
        if (point_in_triangle(px, py,
            prism->vertices[0], prism->vertices[1],
            prism->vertices[2], prism->vertices[3],
            prism->vertices[4], prism->vertices[5])) continue;
      } else {
        if (!point_in_triangle(px, py,
            prism->vertices[0], prism->vertices[1],
            prism->vertices[2], prism->vertices[3],
            prism->vertices[4], prism->vertices[5])) continue;
      }

      float dx = px - origin_x;
      float dy = py - origin_y;
      float pixel_angle = atan2_approx(dy, dx);
      if (pixel_angle < 0) pixel_angle += 2.0f * PI;

      float t;
      if (wrap_around) {
        // Acceptance check uses epsilon-expanded range (a1, a2)
        if (pixel_angle < a1 && pixel_angle > a2) continue;
        // Interpolation uses original boundary (a1_orig) so t=0 at actual first ray
        if (pixel_angle >= a1_orig) {
          t = (pixel_angle - a1_orig) / angle_span;
        } else {
          t = (2.0f * PI - a1_orig + pixel_angle) / angle_span;
        }
      } else {
        // Acceptance check uses epsilon-expanded range (a1, a2)
        if (pixel_angle < a1 || pixel_angle > a2) continue;
        // Interpolation uses original boundary (a1_orig) so t=0 at actual first ray
        t = (pixel_angle - a1_orig) / angle_span;
      }

      // Reverse t if angles were swapped
      if (reverse) t = 1.0f - t;

      // Note: t is NOT clamped to [0,1] here - values outside this range
      // represent the infrared/ultraviolet zones and are handled by extrapolation
      // in interpolate_rainbow_color()

      // Remap t for centered band spacing:
      // Input t ∈ [0,1] spans full spread (infrared edge to ultraviolet edge)
      // Output t_color maps band positions to [0,1]: red ray at 0, violet ray at 1
      // Formula: t_color = (t * N - 0.5) / (N - 1)
      // This gives t_color < 0 for infrared zone, t_color > 1 for ultraviolet zone
      float t_color = (t * (float)NUM_BANDS - 0.5f) / (float)(NUM_BANDS - 1);

      // When reverse_spectrum is true, reverse the color lookup (album art style)
      if (reverse_spectrum) t_color = 1.0f - t_color;

      // Interpolate between rainbow bands (handles extrapolation for t outside [0,1])
      RGB_Linear color = interpolate_rainbow_color(t_color);

      // Additive blend (merges with ray glows for smooth transitions)
      int idx = (y * width + x) * 4;
      fb[idx] += color.r * intensity;
      fb[idx + 1] += color.g * intensity;
      fb[idx + 2] += color.b * intensity;
    }
  }
}
