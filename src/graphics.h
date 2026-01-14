#pragma once

#include "math.h"

// =================================================================================================
// Wavelength Constants
// =================================================================================================

// Visible spectrum wavelengths in nanometers: red (650nm) through violet (420nm)
#define NUM_WAVELENGTHS 8
static const float WAVELENGTHS[NUM_WAVELENGTHS] = {
  650.0f, 600.0f, 570.0f, 540.0f,
  510.0f, 480.0f, 450.0f, 420.0f
};

// =================================================================================================
// Wavelength to RGB
// =================================================================================================

typedef struct { uint8_t r, g, b; } RGB;

static RGB wavelength_to_rgb(float wavelength_nm) {
  float r = 0.0f, g = 0.0f, b = 0.0f;

  if (wavelength_nm >= 380.0f && wavelength_nm < 440.0f) {
    r = -(wavelength_nm - 440.0f) / 60.0f;
    b = 1.0f;
  } else if (wavelength_nm >= 440.0f && wavelength_nm < 490.0f) {
    g = (wavelength_nm - 440.0f) / 50.0f;
    b = 1.0f;
  } else if (wavelength_nm >= 490.0f && wavelength_nm < 510.0f) {
    g = 1.0f;
    b = -(wavelength_nm - 510.0f) / 20.0f;
  } else if (wavelength_nm >= 510.0f && wavelength_nm < 580.0f) {
    r = (wavelength_nm - 510.0f) / 70.0f;
    g = 1.0f;
  } else if (wavelength_nm >= 580.0f && wavelength_nm < 645.0f) {
    r = 1.0f;
    g = -(wavelength_nm - 645.0f) / 65.0f;
  } else if (wavelength_nm >= 645.0f && wavelength_nm <= 780.0f) {
    r = 1.0f;
  }

  float factor = 0.0f;
  if (wavelength_nm >= 380.0f && wavelength_nm < 420.0f) {
    factor = 0.3f + 0.7f * (wavelength_nm - 380.0f) / 40.0f;
  } else if (wavelength_nm >= 420.0f && wavelength_nm < 700.0f) {
    factor = 1.0f;
  } else if (wavelength_nm >= 700.0f && wavelength_nm <= 780.0f) {
    factor = 0.3f + 0.7f * (780.0f - wavelength_nm) / 80.0f;
  }

  RGB result;
  float out_r = fast_powf(r * factor, 0.8f) * 255.0f;
  float out_g = fast_powf(g * factor, 0.8f) * 255.0f;
  float out_b = fast_powf(b * factor, 0.8f) * 255.0f;
  result.r = out_r > 255.0f ? 255 : (uint8_t)out_r;
  result.g = out_g > 255.0f ? 255 : (uint8_t)out_g;
  result.b = out_b > 255.0f ? 255 : (uint8_t)out_b;
  return result;
}

// =================================================================================================
// Pixel Operations
// =================================================================================================

// Additive blending: adds color to existing pixels, creating glow effects.
// Use for single continuous lines (light beams) where pixels aren't drawn twice.
static inline void set_pixel_additive(
  uint8_t* fb, int width, int height,
  int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  if (x < 0 || x >= width || y < 0 || y >= height) return;

  int idx = (y * width + x) * 4;
  uint32_t ar = (uint32_t)r * a / 255;
  uint32_t ag = (uint32_t)g * a / 255;
  uint32_t ab = (uint32_t)b * a / 255;

  uint32_t nr = (uint32_t)fb[idx] + ar;
  uint32_t ng = (uint32_t)fb[idx + 1] + ag;
  uint32_t nb = (uint32_t)fb[idx + 2] + ab;

  fb[idx] = nr > 255 ? 255 : (uint8_t)nr;
  fb[idx + 1] = ng > 255 ? 255 : (uint8_t)ng;
  fb[idx + 2] = nb > 255 ? 255 : (uint8_t)nb;
}

// Alpha blending: standard "over" compositing for solid elements.
// Use for multi-segment lines (gradients) to avoid bright dots at segment overlaps.
static inline void set_pixel_alpha(
  uint8_t* fb, int width, int height,
  int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  if (x < 0 || x >= width || y < 0 || y >= height) return;

  int idx = (y * width + x) * 4;

  if (a == 255) {
    fb[idx] = r;
    fb[idx + 1] = g;
    fb[idx + 2] = b;
    fb[idx + 3] = 255;
  } else {
    uint32_t alpha = a;
    uint32_t inv_alpha = 255 - a;
    fb[idx] = (uint8_t)((r * alpha + fb[idx] * inv_alpha) / 255);
    fb[idx + 1] = (uint8_t)((g * alpha + fb[idx + 1] * inv_alpha) / 255);
    fb[idx + 2] = (uint8_t)((b * alpha + fb[idx + 2] * inv_alpha) / 255);
    fb[idx + 3] = 255;
  }
}

// =================================================================================================
// Geometry Helpers
// =================================================================================================

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
  float t = ((px - x0) * dx + (py - y0) * dy) / len_sq;
  if (t < 0.0f) t = 0.0f;
  if (t > 1.0f) t = 1.0f;

  float proj_x = x0 + t * dx;
  float proj_y = y0 + t * dy;

  float dist_x = px - proj_x;
  float dist_y = py - proj_y;
  return sqrtf_impl(dist_x * dist_x + dist_y * dist_y);
}

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
// Line Drawing (Bresenham)
// =================================================================================================

static void draw_line_alpha(
  uint8_t* fb, int width, int height,
  int x0, int y0, int x1, int y1,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  int dx = x1 > x0 ? x1 - x0 : x0 - x1;
  int dy = y1 > y0 ? y1 - y0 : y0 - y1;
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx - dy;

  while (1) {
    set_pixel_alpha(fb, width, height, x0, y0, r, g, b, a);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}

static void draw_line_additive(
  uint8_t* fb, int width, int height,
  int x0, int y0, int x1, int y1,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  int dx = x1 > x0 ? x1 - x0 : x0 - x1;
  int dy = y1 > y0 ? y1 - y0 : y0 - y1;
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx - dy;

  while (1) {
    set_pixel_additive(fb, width, height, x0, y0, r, g, b, a);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}

// =================================================================================================
// Line Drawing with Glow (Distance Field, Additive Blending)
// =================================================================================================

// Draw a line with glow effect using distance field approach and additive blending.
// Uses additive blending for both glow and crisp line - designed for light rays where
// drawing multiple overlapping rays (e.g., per-wavelength) accumulates to correct brightness.
// clip_triangle: if non-NULL, points to 6 floats (v0x,v0y,v1x,v1y,v2x,v2y) to clip glow inside
// clip_circle: if non-NULL, points to 3 floats (cx,cy,radius) to clip glow inside circle
// exclude_triangle: if non-NULL, points to 6 floats to exclude glow from inside this triangle
// glow_width: how far the glow extends perpendicular to the line (in pixels)
// intensity: 0.0-1.0 multiplier for glow brightness
// falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
static void draw_line_with_glow_additive(
  uint8_t* fb, int width, int height,
  float x0, float y0, float x1, float y1,
  uint8_t r, uint8_t g, uint8_t b,
  float glow_width,
  float intensity,
  int falloff,
  const float* clip_triangle,
  const float* clip_circle,
  const float* exclude_triangle
) {
  // Compute bounding box expanded by glow width
  float min_x = (x0 < x1 ? x0 : x1) - glow_width;
  float max_x = (x0 > x1 ? x0 : x1) + glow_width;
  float min_y = (y0 < y1 ? y0 : y1) - glow_width;
  float max_y = (y0 > y1 ? y0 : y1) + glow_width;

  // Clamp to screen bounds
  int x_start = (int)min_x - 1;
  int x_end = (int)max_x + 2;
  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (x_start < 0) x_start = 0;
  if (y_start < 0) y_start = 0;
  if (x_end > width) x_end = width;
  if (y_end > height) y_end = height;

  // Iterate over bounding box and apply glow
  for (int y = y_start; y < y_end; y++) {
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;

      // Skip pixels outside the clipping triangle (if provided)
      if (clip_triangle && !point_in_triangle(px, py,
          clip_triangle[0], clip_triangle[1],
          clip_triangle[2], clip_triangle[3],
          clip_triangle[4], clip_triangle[5])) {
        continue;
      }

      // Skip pixels outside the clipping circle (if provided)
      if (clip_circle) {
        float dx = px - clip_circle[0];
        float dy = py - clip_circle[1];
        if (dx * dx + dy * dy > clip_circle[2] * clip_circle[2]) {
          continue;
        }
      }

      // Skip pixels inside the exclusion triangle (if provided)
      if (exclude_triangle && point_in_triangle(px, py,
          exclude_triangle[0], exclude_triangle[1],
          exclude_triangle[2], exclude_triangle[3],
          exclude_triangle[4], exclude_triangle[5])) {
        continue;
      }

      // Compute distance to line segment
      float dist = point_to_segment_distance(px, py, x0, y0, x1, y1);

      // Apply glow: intensity falls off with distance from line
      if (dist < glow_width) {
        float t = dist / glow_width;
        float falloff_value;

        switch (falloff) {
          case 0:  // Linear
            falloff_value = 1.0f - t;
            break;
          case 1:  // Quadratic
            falloff_value = (1.0f - t) * (1.0f - t);
            break;
          case 2:  // Cubic
            falloff_value = (1.0f - t) * (1.0f - t) * (1.0f - t);
            break;
          case 3:  // Exponential
            falloff_value = fast_powf(2.718281828f, -3.0f * t) * (1.0f - t);
            break;
          default:
            falloff_value = (1.0f - t) * (1.0f - t);
        }

        uint8_t alpha = (uint8_t)(falloff_value * intensity * 255.0f);
        set_pixel_additive(fb, width, height, x, y, r, g, b, alpha);
      }
    }
  }

  // Draw crisp line on top for definition (additive for wavelength mixing)
  draw_line_additive(fb, width, height,
    (int)(x0 + 0.5f), (int)(y0 + 0.5f),
    (int)(x1 + 0.5f), (int)(y1 + 0.5f),
    r, g, b, 255);
}

// =================================================================================================
// Watch-Specific Drawing
// =================================================================================================

// Simple hash function for deterministic noise/stars
static inline uint32_t hash_pixel(int x, int y) {
  uint32_t h = (uint32_t)(x * 374761393 + y * 668265263);
  h = (h ^ (h >> 13)) * 1274126177;
  return h ^ (h >> 16);
}

static void init_watch_framebuffer(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius,
  float grain_intensity,    // 0.0-1.0
  float vignette_intensity, // 0.0-1.0
  int white_background      // 1 = white background (for pebble mode with dithering)
) {
  // Base colors
  float watch_base = 10.0f;
  float bg_base = white_background ? 255.0f : 35.0f;

  // Vignette parameters (for background)
  float max_dist = sqrtf_impl((float)(width * width + height * height)) * 0.5f;
  float vignette_strength = vignette_intensity * 0.4f;  // Max 40% darkening at corners

  // Grain strength: ±15 at full intensity
  float grain_strength = grain_intensity * 15.0f;

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;
      int idx = row_offset + x * 4;

      // Film grain: subtle brightness variation
      uint32_t hash = hash_pixel(x, y);
      float grain = ((float)(hash & 0xFF) / 255.0f - 0.5f) * grain_strength * 2.0f;

      float final_val;
      if (dist2 <= r2) {
        // Inside watchface - dark with grain
        final_val = watch_base + grain;
      } else {
        // Outside watchface - vignette + grain
        float dist_from_center = sqrtf_impl(dist2);
        float vignette_t = (dist_from_center - radius) / (max_dist - radius);
        if (vignette_t < 0.0f) vignette_t = 0.0f;
        if (vignette_t > 1.0f) vignette_t = 1.0f;
        float vignette = 1.0f - vignette_t * vignette_strength;

        final_val = bg_base * vignette + grain;
      }

      if (final_val < 0.0f) final_val = 0.0f;
      if (final_val > 255.0f) final_val = 255.0f;

      uint8_t val = (uint8_t)final_val;
      fb[idx] = val;
      fb[idx + 1] = val;
      fb[idx + 2] = val;
      fb[idx + 3] = 255;
    }
  }
}

static void stroke_prism(
  uint8_t* fb, int width, int height,
  const Prism* prism,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    int x0 = (int)(prism->vertices[i * 2] + 0.5f);
    int y0 = (int)(prism->vertices[i * 2 + 1] + 0.5f);
    int x1 = (int)(prism->vertices[j * 2] + 0.5f);
    int y1 = (int)(prism->vertices[j * 2 + 1] + 0.5f);
    draw_line_alpha(fb, width, height, x0, y0, x1, y1, r, g, b, a);
  }
}

// =================================================================================================
// Prism Inner Glow (Distance Field)
// =================================================================================================

// Compute minimum distance from point to any prism edge
static float min_distance_to_prism_edge(float px, float py, const Prism* prism) {
  float min_dist = 1e9f;

  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float x0 = prism->vertices[i * 2];
    float y0 = prism->vertices[i * 2 + 1];
    float x1 = prism->vertices[j * 2];
    float y1 = prism->vertices[j * 2 + 1];

    float dist = point_to_segment_distance(px, py, x0, y0, x1, y1);
    if (dist < min_dist) min_dist = dist;
  }

  return min_dist;
}

// Draw prism with inner glow effect
// glow_width: how far the glow extends inward (in pixels)
// intensity: 0.0-1.0 multiplier for glow brightness
// falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
static void draw_prism_glow(
  uint8_t* fb, int width, int height,
  const Prism* prism,
  uint8_t r, uint8_t g, uint8_t b,
  float glow_width,
  float intensity,
  int falloff
) {
  // Get prism vertices
  float v0x = prism->vertices[0], v0y = prism->vertices[1];
  float v1x = prism->vertices[2], v1y = prism->vertices[3];
  float v2x = prism->vertices[4], v2y = prism->vertices[5];

  // Compute bounding box
  float min_x = v0x < v1x ? (v0x < v2x ? v0x : v2x) : (v1x < v2x ? v1x : v2x);
  float max_x = v0x > v1x ? (v0x > v2x ? v0x : v2x) : (v1x > v2x ? v1x : v2x);
  float min_y = v0y < v1y ? (v0y < v2y ? v0y : v2y) : (v1y < v2y ? v1y : v2y);
  float max_y = v0y > v1y ? (v0y > v2y ? v0y : v2y) : (v1y > v2y ? v1y : v2y);

  // Clamp to screen bounds
  int x_start = (int)min_x - 1;
  int x_end = (int)max_x + 2;
  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (x_start < 0) x_start = 0;
  if (y_start < 0) y_start = 0;
  if (x_end > width) x_end = width;
  if (y_end > height) y_end = height;

  // Iterate over bounding box
  for (int y = y_start; y < y_end; y++) {
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;

      // Check if inside triangle
      if (!point_in_triangle(px, py, v0x, v0y, v1x, v1y, v2x, v2y)) {
        continue;
      }

      // Compute distance to nearest edge
      float dist = min_distance_to_prism_edge(px, py, prism);

      // Apply glow: intensity falls off with distance from edge
      if (dist < glow_width) {
        float t = dist / glow_width;
        float falloff_value;

        switch (falloff) {
          case 0:  // Linear
            falloff_value = 1.0f - t;
            break;
          case 1:  // Quadratic
            falloff_value = (1.0f - t) * (1.0f - t);
            break;
          case 2:  // Cubic
            falloff_value = (1.0f - t) * (1.0f - t) * (1.0f - t);
            break;
          case 3:  // Exponential
            falloff_value = fast_powf(2.718281828f, -3.0f * t) * (1.0f - t);
            break;
          default:
            falloff_value = (1.0f - t) * (1.0f - t);
        }

        uint8_t alpha = (uint8_t)(falloff_value * intensity * 255.0f);
        set_pixel_additive(fb, width, height, x, y, r, g, b, alpha);
      }
    }
  }

  // Draw the edge line on top for crisp boundary
  stroke_prism(fb, width, height, prism, r, g, b, 255);
}

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

static void draw_watch_overlay(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius
) {
  for (int h = 0; h < 12; h++) {
    float angle = ((float)h - 3.0f) * 30.0f * PI / 180.0f;

    float inner_r = radius * 0.92f;
    float outer_r = radius * 0.98f;

    float cos_a = cosf_approx(angle);
    float sin_a = sinf_approx(angle);
    int x0 = (int)(cx + cos_a * inner_r + 0.5f);
    int y0 = (int)(cy + sin_a * inner_r + 0.5f);
    int x1 = (int)(cx + cos_a * outer_r + 0.5f);
    int y1 = (int)(cy + sin_a * outer_r + 0.5f);

    draw_line_alpha(fb, width, height, x0, y0, x1, y1, 100, 100, 100, 255);
  }
}

// =================================================================================================
// Seconds Sparkle on Prism Edge
// =================================================================================================

// Compute position on prism edge for a given second (0-60).
// The sparkle travels clockwise from the apex:
//   0-20s: Edge 0 (v0→v1, apex to bottom-right)
//   20-40s: Edge 1 (v1→v2, bottom-right to bottom-left)
//   40-60s: Edge 2 (v2→v0, bottom-left back to apex)
static void compute_sparkle_position(
  float second,
  const Prism* prism,
  float* out_x, float* out_y
) {
  // Wrap seconds to [0, 60)
  while (second >= 60.0f) second -= 60.0f;
  while (second < 0.0f) second += 60.0f;

  int edge;
  float t;

  if (second < 20.0f) {
    edge = 0;  // v0 → v1
    t = second / 20.0f;
  } else if (second < 40.0f) {
    edge = 1;  // v1 → v2
    t = (second - 20.0f) / 20.0f;
  } else {
    edge = 2;  // v2 → v0
    t = (second - 40.0f) / 20.0f;
  }

  int v_start = edge;
  int v_end = (edge + 1) % 3;

  float x0 = prism->vertices[v_start * 2];
  float y0 = prism->vertices[v_start * 2 + 1];
  float x1 = prism->vertices[v_end * 2];
  float y1 = prism->vertices[v_end * 2 + 1];

  *out_x = x0 + t * (x1 - x0);
  *out_y = y0 + t * (y1 - y0);
}

// Draw a diamond-like sparkle with 4-pointed star rays and twinkling animation.
// Creates a gem-like highlight that pops above other glow effects.
static void draw_sparkle(
  uint8_t* fb, int width, int height,
  float x, float y,
  float radius,        // Watch radius for base scaling
  float size_percent,  // 1.0-10.0 size multiplier
  float second         // Fractional second for twinkle animation
) {
  int cx = (int)(x + 0.5f);
  int cy = (int)(y + 0.5f);

  // Scale sparkle size using square root for sub-linear scaling
  // This keeps sparkle proportionally similar across screen sizes
  // (sqrt grows slower than linear, so large screens don't get huge sparkles)
  float base_size = sqrtf_impl(radius) / 3.0f;
  if (base_size < 1.0f) base_size = 1.0f;

  // Apply user size multiplier
  base_size *= size_percent;

  // Twinkle animation: pulsing intensity based on fractional seconds
  // Use a fast sine wave for sparkle effect (cycles ~4 times per second)
  float frac = second - (float)(int)second;  // 0.0 to 1.0
  float twinkle = 0.7f + 0.3f * sinf_approx(frac * TAU * 4.0f);

  // Star ray lengths (4-pointed star)
  int ray_length = (int)(base_size * 2.0f);
  int short_ray = (int)(base_size * 1.2f);  // Diagonal rays slightly shorter
  int core_radius = (int)(base_size * 0.6f);
  if (core_radius < 1) core_radius = 1;

  // Draw the 4 main star rays (vertical and horizontal)
  // These are the signature diamond sparkle lines
  for (int i = 1; i <= ray_length; i++) {
    float falloff = 1.0f - ((float)i / (float)(ray_length + 1));
    falloff = falloff * falloff;  // Quadratic falloff for sharper rays
    uint8_t alpha = (uint8_t)(falloff * twinkle * 255.0f);

    // Vertical rays
    set_pixel_additive(fb, width, height, cx, cy - i, 255, 255, 255, alpha);
    set_pixel_additive(fb, width, height, cx, cy + i, 255, 255, 255, alpha);
    // Horizontal rays
    set_pixel_additive(fb, width, height, cx - i, cy, 255, 255, 255, alpha);
    set_pixel_additive(fb, width, height, cx + i, cy, 255, 255, 255, alpha);
  }

  // Draw 4 diagonal rays (45 degree angles) - slightly shorter
  for (int i = 1; i <= short_ray; i++) {
    float falloff = 1.0f - ((float)i / (float)(short_ray + 1));
    falloff = falloff * falloff * falloff;  // Cubic falloff for even sharper diagonals
    uint8_t alpha = (uint8_t)(falloff * twinkle * 200.0f);

    set_pixel_additive(fb, width, height, cx - i, cy - i, 255, 255, 255, alpha);
    set_pixel_additive(fb, width, height, cx + i, cy - i, 255, 255, 255, alpha);
    set_pixel_additive(fb, width, height, cx - i, cy + i, 255, 255, 255, alpha);
    set_pixel_additive(fb, width, height, cx + i, cy + i, 255, 255, 255, alpha);
  }

  // Draw bright glowing core
  for (int dy = -core_radius; dy <= core_radius; dy++) {
    for (int dx = -core_radius; dx <= core_radius; dx++) {
      float dist = sqrtf_impl((float)(dx * dx + dy * dy));
      if (dist > (float)core_radius) continue;

      // Intense core with soft edge
      float intensity = 1.0f - (dist / ((float)core_radius + 0.5f));
      intensity = intensity * intensity;  // Concentrate brightness at center
      uint8_t alpha = (uint8_t)(intensity * twinkle * 255.0f);

      set_pixel_additive(fb, width, height, cx + dx, cy + dy, 255, 255, 255, alpha);
    }
  }

  // Draw super-bright center pixels (the diamond's "fire")
  uint8_t center_alpha = (uint8_t)(twinkle * 255.0f);
  set_pixel_additive(fb, width, height, cx, cy, 255, 255, 255, center_alpha);
  set_pixel_additive(fb, width, height, cx, cy, 255, 255, 255, center_alpha);  // Double-add for extra brightness
}

// =================================================================================================
// Watchface Rendering
// =================================================================================================

// Maximum spread in radians (30 degrees)
#define MAX_SPREAD_RAD (30.0f * PI / 180.0f)

// Internal fan spread factor (how much colors separate inside prism)
#define INTERNAL_FAN_FACTOR 0.15f

// Compute the exit angle for a given wavelength index.
// Returns angle that fans around the hour_angle based on spread.
static float compute_exit_angle(
  float hour_angle,
  float rainbow_spread,  // 0.0 to 1.0
  int wavelength_idx,    // 0 = red, NUM_WAVELENGTHS-1 = violet
  int artistic_dispersion // 1 = artistic (red at negative offset), 0 = physical (violet bends most)
) {
  float spread_rad = rainbow_spread * MAX_SPREAD_RAD;

  // t: 0 for red (first), 1 for violet (last)
  float t = (float)wavelength_idx / (float)(NUM_WAVELENGTHS - 1);

  // Artistic: red (t=0) at negative offset, violet (t=1) at positive offset
  // Physical: violet bends most (negative offset), red bends least (positive offset)
  float offset = artistic_dispersion ? (t - 0.5f) * spread_rad : (0.5f - t) * spread_rad;

  return hour_angle + offset;
}

// Render the watchface scene.
// - entry_x, entry_y: minute hand position (light source)
// - hour_angle: angle to hour position from center
// - rainbow_spread: 0.0 (no spread) to 1.0 (30 degree spread)
// - second: 0.0-59.999 for seconds sparkle position on prism edge
// - show_markers: if true, show watch overlay (hour markers)
// - prism_r, prism_g, prism_b: RGB values (0-255) for prism stroke and internal rays
// - show_seconds: if true, show seconds sparkle on prism edge
// - sparkle_size_percent: 1.0-10.0 scale factor for sparkle size
// - ray_glow_width: glow width for rays in pixels
// - ray_glow_intensity: 0.0-1.0 multiplier for ray glow brightness
// - ray_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - internal_ray_real_colors: if true, use wavelength-based colors for internal rays
// - grain_intensity: 0.0-1.0 intensity of film grain effect
// - vignette_intensity: 0.0-1.0 intensity of vignette darkening
// - white_background: 1 = white background (for pebble mode with dithering)
static void render_watchface_scene(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius,
  float entry_x, float entry_y,
  float hour_angle,
  float rainbow_spread,
  float second,
  const Prism* prism,
  int show_markers,
  uint8_t prism_r,
  uint8_t prism_g,
  uint8_t prism_b,
  int show_seconds,
  float sparkle_size_percent,
  float glow_width_percent,
  float glow_intensity,
  int glow_falloff,
  float ray_glow_width,
  float ray_glow_intensity,
  int ray_glow_falloff,
  int internal_ray_real_colors,
  int artistic_dispersion,
  float grain_intensity,
  float vignette_intensity,
  int white_background
) {
  // Initialize background
  init_watch_framebuffer(fb, width, height, cx, cy, radius, grain_intensity, vignette_intensity, white_background);

  // Entry ray direction: toward center
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  // Find where entry ray hits prism
  RayHit prism_entry = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, prism);

  if (!prism_entry.hit) {
    // Ray doesn't hit prism - just draw overlay and return
    draw_prism_glow(fb, width, height, prism, prism_r, prism_g, prism_b,
                    radius * glow_width_percent, glow_intensity, glow_falloff);
    if (show_markers) {
      draw_watch_overlay(fb, width, height, cx, cy, radius);
    }
    return;
  }

  // Clipping data for external rays (entry ray and rainbow rays)
  float circle_clip[3] = { cx, cy, radius };

  // Clip incoming ray once (shared by all wavelengths)
  float clip_x0, clip_y0, clip_x1, clip_y1;
  int has_clipped_entry = clip_segment_to_circle(
    entry_x, entry_y, prism_entry.px, prism_entry.py,
    cx, cy, radius,
    &clip_x0, &clip_y0, &clip_x1, &clip_y1
  );

  // Compute bounce decision once using guiding ray (before wavelength loop)
  BounceInfo bounce = compute_bounce_info(
    prism_entry.edge_idx, prism_entry.u,
    hour_angle,
    prism
  );

  // Draw all rays per-wavelength for consistent brightness (additive blending)
  // Outside ray: always white (all wavelengths add to white)
  // Internal rays: use wavelength colors if toggle on, otherwise prism color
  for (int i = 0; i < NUM_WAVELENGTHS; i++) {
    float wavelength = WAVELENGTHS[i];
    RGB color = wavelength_to_rgb(wavelength);

    // Draw incoming ray (outside prism) - white for all wavelengths, adds up via blending
    if (has_clipped_entry) {
      draw_line_with_glow_additive(fb, width, height,
        clip_x0, clip_y0, clip_x1, clip_y1,
        200, 200, 200, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
        0, circle_clip, prism->vertices);
    }

    // Compute exit angle for this wavelength
    float exit_angle = compute_exit_angle(hour_angle, rainbow_spread, i, artistic_dispersion);

    // Find where exit ray (from center) exits the prism
    RayHit prism_exit = find_prism_exit_from_center(cx, cy, exit_angle, prism);

    if (prism_exit.hit) {
      // Internal path: from entry point to exit point (inside prism)
      // Apply slight internal fan for visual effect
      float internal_t = (float)i / (float)(NUM_WAVELENGTHS - 1);
      float internal_spread = rainbow_spread * INTERNAL_FAN_FACTOR * MAX_SPREAD_RAD;
      float internal_offset = (0.5f - internal_t) * internal_spread;

      // Adjust internal endpoint slightly based on wavelength
      float internal_exit_x = prism_exit.px + cosf_approx(exit_angle + PI/2) * internal_offset * 2.0f;
      float internal_exit_y = prism_exit.py + sinf_approx(exit_angle + PI/2) * internal_offset * 2.0f;

      // Use wavelength colors if internal_ray_real_colors is set, otherwise use prism colors
      uint8_t internal_r = internal_ray_real_colors ? color.r : prism_r;
      uint8_t internal_g = internal_ray_real_colors ? color.g : prism_g;
      uint8_t internal_b = internal_ray_real_colors ? color.b : prism_b;

      if (bounce.needs_bounce) {
        // Draw entry→bounce segment per-wavelength for consistent brightness
        draw_line_with_glow_additive(fb, width, height,
          prism_entry.px, prism_entry.py,
          bounce.bounce_x, bounce.bounce_y,
          internal_r, internal_g, internal_b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);
        // Bounced path: bounce -> exit (spread happens here)
        draw_line_with_glow_additive(fb, width, height,
          bounce.bounce_x, bounce.bounce_y,
          internal_exit_x, internal_exit_y,
          internal_r, internal_g, internal_b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);
      } else {
        // Direct path: entry -> exit
        draw_line_with_glow_additive(fb, width, height,
          prism_entry.px, prism_entry.py,
          internal_exit_x, internal_exit_y,
          internal_r, internal_g, internal_b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);
      }

      // Draw exit ray (from prism exit to circle edge) with actual rainbow color
      float exit_dir_x = cosf_approx(exit_angle);
      float exit_dir_y = sinf_approx(exit_angle);

      float border_x, border_y;
      if (ray_circle_intersection(
        prism_exit.px, prism_exit.py,
        exit_dir_x, exit_dir_y,
        cx, cy, radius,
        &border_x, &border_y
      )) {
        float clip_x0, clip_y0, clip_x1, clip_y1;
        if (clip_segment_to_circle(
          prism_exit.px, prism_exit.py, border_x, border_y,
          cx, cy, radius,
          &clip_x0, &clip_y0, &clip_x1, &clip_y1
        )) {
          draw_line_with_glow_additive(fb, width, height,
            clip_x0, clip_y0, clip_x1, clip_y1,
            color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
            0, circle_clip, prism->vertices);
        }
      }
    }
  }

  // Draw prism with inner glow
  draw_prism_glow(fb, width, height, prism, prism_r, prism_g, prism_b,
                  radius * glow_width_percent, glow_intensity, glow_falloff);

  // Draw seconds sparkle on prism edge (if enabled)
  if (show_seconds) {
    float sparkle_x, sparkle_y;
    compute_sparkle_position(second, prism, &sparkle_x, &sparkle_y);
    draw_sparkle(fb, width, height, sparkle_x, sparkle_y, radius, sparkle_size_percent, second);
  }

  // Draw watch overlay (hour markers) if show_markers is set
  if (show_markers) {
    draw_watch_overlay(fb, width, height, cx, cy, radius);
  }
}
