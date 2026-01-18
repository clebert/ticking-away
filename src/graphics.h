#pragma once

#include "math.h"

// =================================================================================================
// Rainbow Colors (7 perceptually balanced bands)
// =================================================================================================

// 7 bands derived from OkLCH with equal hue spacing for perceptual uniformity
#define NUM_BANDS 7

// Color palette presets for rainbow bands
typedef enum {
  PALETTE_OKLCH_BALANCED = 0,  // Current: equal OkLCH hue spacing (friendly)
  PALETTE_SATURATED = 1,       // Higher saturation, more vivid
  PALETTE_SPECTRAL = 2,        // Closer to physical spectrum
  PALETTE_NEON = 3,            // Electric/neon look
  PALETTE_MUTED = 4,           // Desaturated, cinematic
  PALETTE_COUNT
} ColorPalette;

// Palette definitions: [palette][band][rgb] in sRGB
static const uint8_t PALETTE_COLORS[PALETTE_COUNT][NUM_BANDS][3] = {
  // PALETTE_OKLCH_BALANCED (friendly, even OkLCH hue spacing)
  {
    {255,  64,  64},  // Red      (OkLCH hue ~30°)
    {255, 160,   0},  // Orange   (OkLCH hue ~70°)
    {220, 220,   0},  // Yellow   (OkLCH hue ~110°)
    {  0, 200,  80},  // Green    (OkLCH hue ~150°)
    {  0, 180, 220},  // Cyan     (OkLCH hue ~195°)
    { 80, 100, 255},  // Blue     (OkLCH hue ~250°)
    {180,  80, 255}   // Violet   (OkLCH hue ~300°)
  },
  // PALETTE_SATURATED (vivid, punchy)
  {
    {255,   0,   0},  // Pure red
    {255, 128,   0},  // Vivid orange
    {255, 255,   0},  // Pure yellow
    {  0, 255,   0},  // Pure green
    {  0, 255, 255},  // Pure cyan
    {  0,   0, 255},  // Pure blue
    {128,   0, 255}   // Vivid violet
  },
  // PALETTE_SPECTRAL (closer to physical spectrum)
  {
    {255,   0,   0},  // 700nm Red
    {255, 127,   0},  // 620nm Orange
    {255, 255,   0},  // 580nm Yellow
    {  0, 255,   0},  // 530nm Green
    {  0, 127, 255},  // 480nm Cyan-blue
    {  0,   0, 255},  // 450nm Blue
    {139,   0, 255}   // 400nm Violet
  },
  // PALETTE_NEON (electric, oversaturated feel)
  {
    {255,  20,  80},  // Hot pink-red
    {255, 100,   0},  // Neon orange
    {200, 255,   0},  // Lime yellow
    {  0, 255, 100},  // Electric green
    {  0, 200, 255},  // Cyan
    { 50,  50, 255},  // Electric blue
    {200,   0, 255}   // Neon purple
  },
  // PALETTE_MUTED (desaturated, cinematic)
  {
    {200,  80,  80},  // Dusty red
    {200, 140,  70},  // Muted orange
    {180, 180,  80},  // Olive yellow
    { 70, 160, 100},  // Sage green
    { 80, 150, 180},  // Steel cyan
    {100, 110, 200},  // Dusty blue
    {150, 100, 200}   // Muted violet
  }
};

// Edge margin factor for extending gradient beyond visible rays into IR/UV zones
// With centered band spacing, rays span (N-1)/N of the gradient; this extends each edge by 0.5/N
#define EDGE_MARGIN_FACTOR (0.5f / (float)(NUM_BANDS - 1))

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
// Color Types
// =================================================================================================

typedef struct { float r, g, b; } RGB_Linear;

// =================================================================================================
// OkLab Color Space (Perceptually Uniform)
// =================================================================================================

typedef struct { float L, a, b; } OkLab;

// Convert linear RGB to OkLab
static inline OkLab linear_to_oklab(float r, float g, float b) {
  // Linear RGB to LMS (cone responses)
  float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
  float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
  float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;

  // Cube root (perceptual nonlinearity)
  float l_ = cbrtf_impl(l);
  float m_ = cbrtf_impl(m);
  float s_ = cbrtf_impl(s);

  // LMS' to OkLab
  OkLab lab;
  lab.L = 0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_;
  lab.a = 1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_;
  lab.b = 0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_;
  return lab;
}

// Convert OkLab to linear RGB
static inline RGB_Linear oklab_to_linear(OkLab lab) {
  // OkLab to LMS'
  float l_ = lab.L + 0.3963377774f * lab.a + 0.2158037573f * lab.b;
  float m_ = lab.L - 0.1055613458f * lab.a - 0.0638541728f * lab.b;
  float s_ = lab.L - 0.0894841775f * lab.a - 1.2914855480f * lab.b;

  // Cube (inverse of cube root)
  float l = l_ * l_ * l_;
  float m = m_ * m_ * m_;
  float s = s_ * s_ * s_;

  // LMS to linear RGB
  RGB_Linear rgb;
  rgb.r =  4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s;
  rgb.g = -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s;
  rgb.b = -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s;

  // Clamp to valid range (OkLab can produce out-of-gamut values)
  rgb.r = maxf_impl(rgb.r, 0.0f);
  rgb.g = maxf_impl(rgb.g, 0.0f);
  rgb.b = maxf_impl(rgb.b, 0.0f);

  return rgb;
}

// =================================================================================================
// sRGB <-> Linear Conversion (Proper IEC 61966-2-1 standard)
// =================================================================================================

// Convert sRGB (0-255) to linear (0.0-1.0) using proper sRGB transfer function.
// Uses piecewise function: linear region below 0.04045, power curve above.
static inline float srgb_to_linear(uint8_t srgb) {
  float s = (float)srgb / 255.0f;
  if (s <= 0.04045f) {
    return s / 12.92f;
  }
  return fast_powf((s + 0.055f) / 1.055f, 2.4f);
}

// Convert linear (0.0-1.0) to sRGB (0.0-1.0) using proper sRGB transfer function.
// Uses piecewise function: linear region below 0.0031308, power curve above.
// Uses accurate_pow_5_12 instead of fast_powf to eliminate banding in dark regions.
static inline float linear_to_srgb(float linear) {
  if (linear <= 0.0031308f) {
    return linear * 12.92f;
  }
  return 1.055f * accurate_pow_5_12(linear) - 0.055f;
}

// Precomputed linear RGB colors for each band
static RGB_Linear BAND_COLORS_LINEAR[NUM_BANDS];
// Precomputed OkLab colors for perceptually uniform gradient interpolation
static OkLab BAND_COLORS_OKLAB[NUM_BANDS];
static ColorPalette current_palette = PALETTE_OKLCH_BALANCED;
static int band_colors_initialized = 0;

// Initialize rainbow colors from selected palette.
// Precomputes both linear RGB and OkLab representations for efficient blending.
// Reinitializes if palette changes.
static void init_band_colors(ColorPalette palette) {
  // Skip if already initialized with same palette
  if (band_colors_initialized && current_palette == palette) return;

  for (int i = 0; i < NUM_BANDS; i++) {
    BAND_COLORS_LINEAR[i].r = srgb_to_linear(PALETTE_COLORS[palette][i][0]);
    BAND_COLORS_LINEAR[i].g = srgb_to_linear(PALETTE_COLORS[palette][i][1]);
    BAND_COLORS_LINEAR[i].b = srgb_to_linear(PALETTE_COLORS[palette][i][2]);

    // Precompute OkLab for gradient interpolation
    BAND_COLORS_OKLAB[i] = linear_to_oklab(
      BAND_COLORS_LINEAR[i].r,
      BAND_COLORS_LINEAR[i].g,
      BAND_COLORS_LINEAR[i].b
    );
  }

  current_palette = palette;
  band_colors_initialized = 1;
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
  float t = clampf(((px - x0) * dx + (py - y0) * dy) / len_sq, 0.0f, 1.0f);

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
// Line Drawing (Bresenham, Linear Space)
// =================================================================================================

static void draw_line_alpha_f(
  float* fb, int width, int height,
  int x0, int y0, int x1, int y1,
  float r, float g, float b, float a
) {
  int dx = x1 > x0 ? x1 - x0 : x0 - x1;
  int dy = y1 > y0 ? y1 - y0 : y0 - y1;
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx - dy;

  while (1) {
    set_pixel_alpha_f(fb, width, height, x0, y0, r, g, b, a);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}

// =================================================================================================
// Capsule Scanline Intersection (for optimized glow rendering)
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

// =================================================================================================
// Watch-Specific Drawing
// =================================================================================================

// Simple hash function for deterministic noise (dithering, film grain)
static inline uint32_t hash_pixel(int x, int y) {
  uint32_t h = (uint32_t)(x * 374761393 + y * 668265263);
  h = (h ^ (h >> 13)) * 1274126177;
  return h ^ (h >> 16);
}

// Initialize watch framebuffer with background (linear color space, 0.0-1.0 range)
static void init_watch_framebuffer_f(
  float* fb, int width, int height,
  float cx, float cy, float radius,
  float vignette_intensity, // 0.0-1.0
  int white_background      // 1 = white background instead of dark
) {
  // Base colors converted from sRGB to linear space
  // Original sRGB values: watch = 10, bg = 35 (or 255 for white)
  float watch_base = srgb_to_linear(10);
  float bg_base = white_background ? 1.0f : srgb_to_linear(35);

  // Vignette parameters (for background)
  float max_dist = sqrtf_impl((float)(width * width + height * height)) * 0.5f;
  float vignette_strength = vignette_intensity * 0.4f;  // Max 40% darkening at corners

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;
      int idx = row_offset + x * 4;

      float final_val;
      if (dist2 <= r2) {
        // Inside watchface - dark
        final_val = watch_base;
      } else {
        // Outside watchface - vignette
        float dist_from_center = sqrtf_impl(dist2);
        float vignette_t = clampf((dist_from_center - radius) / (max_dist - radius), 0.0f, 1.0f);
        // Smoothstep for perceptually smoother gradient
        float smooth_t = vignette_t * vignette_t * (3.0f - 2.0f * vignette_t);
        float vignette = 1.0f - smooth_t * vignette_strength;

        final_val = bg_base * vignette;
      }

      fb[idx] = final_val;
      fb[idx + 1] = final_val;
      fb[idx + 2] = final_val;
      fb[idx + 3] = 1.0f;
    }
  }
}

// Draw prism outline (linear color space)
static void stroke_prism_f(
  float* fb, int width, int height,
  const Prism* prism,
  float r, float g, float b, float a
) {
  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    int x0 = (int)(prism->vertices[i * 2] + 0.5f);
    int y0 = (int)(prism->vertices[i * 2 + 1] + 0.5f);
    int x1 = (int)(prism->vertices[j * 2] + 0.5f);
    int y1 = (int)(prism->vertices[j * 2 + 1] + 0.5f);
    draw_line_alpha_f(fb, width, height, x0, y0, x1, y1, r, g, b, a);
  }
}

// =================================================================================================
// Prism Inner Glow (Distance Field)
// =================================================================================================

// Polynomial smooth minimum for blending distances near corners.
// Creates continuous gradients by smoothly interpolating between two values
// when they are within 'k' of each other. This eliminates the gradient
// discontinuity (visible crease) that occurs with hard min at corners.
static inline float smooth_min(float a, float b, float k) {
  float h = maxf_impl(k - fabsf_impl(a - b), 0.0f) / k;
  return minf_impl(a, b) - h * h * k * 0.25f;
}

// Compute smooth minimum distance from point to any prism edge.
// Uses smooth_min to blend distances near corners, avoiding the gradient
// discontinuity that causes visible dark creases at vertices.
static float min_distance_to_prism_edge(float px, float py, const Prism* prism, float smooth_k) {
  float d0 = point_to_segment_distance(px, py,
    prism->vertices[0], prism->vertices[1],
    prism->vertices[2], prism->vertices[3]);
  float d1 = point_to_segment_distance(px, py,
    prism->vertices[2], prism->vertices[3],
    prism->vertices[4], prism->vertices[5]);
  float d2 = point_to_segment_distance(px, py,
    prism->vertices[4], prism->vertices[5],
    prism->vertices[0], prism->vertices[1]);

  // Chain smooth_min for all three edges
  return smooth_min(smooth_min(d0, d1, smooth_k), d2, smooth_k);
}

// Draw prism with inner glow effect (linear color space)
// glow_width: how far the glow extends inward (in pixels)
// intensity: 0.0-1.0 multiplier for glow brightness
// falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
static void draw_prism_glow_f(
  float* fb, int width, int height,
  const Prism* prism,
  float r, float g, float b,
  float glow_width,
  float intensity,
  int falloff
) {
  float v0x = prism->vertices[0], v0y = prism->vertices[1];
  float v1x = prism->vertices[2], v1y = prism->vertices[3];
  float v2x = prism->vertices[4], v2y = prism->vertices[5];

  float min_x = v0x < v1x ? (v0x < v2x ? v0x : v2x) : (v1x < v2x ? v1x : v2x);
  float max_x = v0x > v1x ? (v0x > v2x ? v0x : v2x) : (v1x > v2x ? v1x : v2x);
  float min_y = v0y < v1y ? (v0y < v2y ? v0y : v2y) : (v1y < v2y ? v1y : v2y);
  float max_y = v0y > v1y ? (v0y > v2y ? v0y : v2y) : (v1y > v2y ? v1y : v2y);

  int x_start = (int)min_x - 1;
  int x_end = (int)max_x + 2;
  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (x_start < 0) x_start = 0;
  if (y_start < 0) y_start = 0;
  if (x_end > width) x_end = width;
  if (y_end > height) y_end = height;

  for (int y = y_start; y < y_end; y++) {
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;

      if (!point_in_triangle(px, py, v0x, v0y, v1x, v1y, v2x, v2y)) {
        continue;
      }

      float dist = min_distance_to_prism_edge(px, py, prism, glow_width * 0.5f);

      if (dist < glow_width) {
        float t = dist / glow_width;
        float falloff_value = compute_falloff(falloff, t);

        float alpha = falloff_value * intensity;
        set_pixel_additive_f(fb, width, height, x, y, r, g, b, alpha);
      }
    }
  }

  // Draw the edge line on top for crisp boundary
  stroke_prism_f(fb, width, height, prism, r, g, b, 1.0f);
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

// Draw watch overlay (hour markers) - linear color space
// Uses pure white for clean, simple rendering.
// Always draws all 12 hour markers.
static void draw_watch_overlay_f(
  float* fb, int width, int height,
  float cx, float cy, float radius,
  float marker_length_percent,
  float marker_glow_width,
  float marker_glow_intensity,
  int marker_glow_falloff
) {
  float glow_width = radius * marker_glow_width;
  float circle_clip[3] = { cx, cy, radius };

  for (int h = 0; h < 12; h++) {
    float angle = ((float)h - 3.0f) * 30.0f * PI / 180.0f;
    float inner_r = radius * (1.0f - marker_length_percent);
    float outer_r = radius * 0.98f;

    float cos_a = cosf_approx(angle);
    float sin_a = sinf_approx(angle);
    float x0 = cx + cos_a * inner_r;
    float y0 = cy + sin_a * inner_r;
    float x1 = cx + cos_a * outer_r;
    float y1 = cy + sin_a * outer_r;

    // Draw with pure white
    draw_line_with_glow_additive_f(fb, width, height,
      x0, y0, x1, y1,
      1.0f, 1.0f, 1.0f,
      glow_width, marker_glow_intensity, marker_glow_falloff,
      0, circle_clip, 0);
  }
}

// =================================================================================================
// Rainbow Ray Geometry
// =================================================================================================

// Maximum spread in radians (30 degrees)
#define MAX_SPREAD_RAD (30.0f * PI / 180.0f)

// Internal fan spread factor (how much colors separate inside prism)
#define INTERNAL_FAN_FACTOR 0.15f

// Compute the exit angle for a given position t within the spread.
// t=0 is the infrared edge, t=1 is the ultraviolet edge.
// Returns angle that fans around the hour_angle based on spread.
// Uses physical dispersion: violet bends most (negative offset), red bends least (positive offset).
static float compute_exit_angle_t(
  float hour_angle,
  float rainbow_spread,  // 0.0 to 1.0
  float t                // 0.0 = infrared edge, 1.0 = ultraviolet edge
) {
  float spread_rad = rainbow_spread * MAX_SPREAD_RAD;
  // Physical: t=0 (infrared) gets positive offset, t=1 (ultraviolet) gets negative
  float offset = (0.5f - t) * spread_rad;
  return hour_angle + offset;
}

// Compute the exit angle for a given band index.
// Uses centered spacing so edge bands (red/violet) aren't clipped at spread boundaries.
// Band 0 (red) maps to t=0.5/N, Band N-1 (violet) maps to t=(N-0.5)/N.
static float compute_exit_angle(
  float hour_angle,
  float rainbow_spread,  // 0.0 to 1.0
  int band_idx           // 0 = red, NUM_BANDS-1 = violet
) {
  // Centered spacing: t = (i + 0.5) / N instead of i / (N-1)
  // This keeps edge bands away from the boundaries (e.g., for 7 bands: 0.071 to 0.929)
  float t = ((float)band_idx + 0.5f) / (float)NUM_BANDS;
  return compute_exit_angle_t(hour_angle, rainbow_spread, t);
}

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

  // Expand acceptance range by epsilon to ensure boundary pixels are included
  float eps = 0.002f;
  a1 -= eps;
  a2 += eps;
  if (a1 < 0) a1 += 2.0f * PI;
  if (a2 >= 2.0f * PI) a2 -= 2.0f * PI;

  int wrap_around = (a1 > a2);

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

// =================================================================================================
// Framebuffer Conversion (Linear → Gamma)
// =================================================================================================

// Convert float framebuffer (linear space) to uint8_t framebuffer (gamma-corrected sRGB).
// Applies proper sRGB transfer function with optional film grain in perceptual (sRGB) space.
// Grain is applied AFTER gamma correction for authentic film grain look (perceptually uniform).
// Vignette dithering is also applied in sRGB space to eliminate banding in dark gradients.
static void finalize_framebuffer(
  const float* float_fb, uint8_t* out_fb,
  int width, int height,
  float grain_intensity,    // 0.0-1.0
  float grain_scale,        // DPR to scale grain (1.0 = no scaling)
  float cx, float cy, float radius,  // Watch circle for grain region
  int apply_vignette_dither,  // 1 = dither vignette region (outside circle)
  const Prism* prism,       // Prism for grain_prism_only mode (can be NULL)
  int grain_prism_only      // 1 = only apply grain inside prism
) {
  // Grain strength in sRGB space: ±6% at full intensity (≈ ±15/255, classic film grain)
  // Applied in perceptual space for uniform noise across all brightness levels.
  float grain_strength = grain_intensity * 0.06f;

  // Brightness threshold (0-1) at which grain reaches full intensity.
  // Below this, grain fades linearly to zero (avoids noise on black areas).
  // Lower = more grain on dark pixels, higher = grain only on bright pixels.
  float grain_brightness_threshold = 0.25f;
  float grain_brightness_scale = 1.0f / grain_brightness_threshold;
  int apply_grain = grain_intensity > 0.0f;

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int i = (y * width + x) * 4;

      // Clamp values (additive blending can exceed 1.0)
      float r = clampf(float_fb[i], 0.0f, 1.0f);
      float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
      float b = clampf(float_fb[i + 2], 0.0f, 1.0f);

      // Apply proper sRGB gamma correction (linear -> sRGB)
      float out_r = linear_to_srgb(r);
      float out_g = linear_to_srgb(g);
      float out_b = linear_to_srgb(b);

      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;
      float dx = px - cx;
      float dy = py - cy;
      float dist_sq = dx * dx + dy * dy;

      // Apply film grain in sRGB space (perceptually uniform)
      // Grain is scaled by pixel brightness to avoid noise on black areas
      int in_grain_region = dist_sq <= r2;
      if (grain_prism_only && prism) {
        in_grain_region = in_grain_region && point_in_triangle(px, py,
          prism->vertices[0], prism->vertices[1],
          prism->vertices[2], prism->vertices[3],
          prism->vertices[4], prism->vertices[5]);
      }
      if (apply_grain && in_grain_region) {
        float brightness = (out_r + out_g + out_b) / 3.0f;
        float brightness_scale = clampf(brightness * grain_brightness_scale, 0.0f, 1.0f);

        int gx = (int)((float)x / grain_scale);
        int gy = (int)((float)y / grain_scale);
        uint32_t hash = hash_pixel(gx, gy);
        float grain = ((float)(hash & 0xFF) / 255.0f - 0.5f) * grain_strength * 2.0f * brightness_scale;

        out_r += grain;
        out_g += grain;
        out_b += grain;
      }

      // Apply vignette dithering in sRGB space (outside watch circle)
      // Dither amplitude ±0.5/255 to break up quantization banding
      if (apply_vignette_dither && dist_sq > r2) {
        uint32_t hash = hash_pixel(x, y);
        float dither = ((float)(hash & 0xFF) / 255.0f - 0.5f) * (2.0f / 255.0f);
        out_r += dither;
        out_g += dither;
        out_b += dither;
      }

      // Quantize to 8-bit
      float final_r = out_r * 255.0f + 0.5f;
      float final_g = out_g * 255.0f + 0.5f;
      float final_b = out_b * 255.0f + 0.5f;

      // Clamp and store
      out_fb[i] = final_r < 0.0f ? 0 : (final_r > 255.0f ? 255 : (uint8_t)final_r);
      out_fb[i + 1] = final_g < 0.0f ? 0 : (final_g > 255.0f ? 255 : (uint8_t)final_g);
      out_fb[i + 2] = final_b < 0.0f ? 0 : (final_b > 255.0f ? 255 : (uint8_t)final_b);
      out_fb[i + 3] = 255;  // Fully opaque
    }
  }
}

// =================================================================================================
// Watchface Rendering
// =================================================================================================

// Render the watchface scene.
// - entry_x, entry_y: minute hand position (light source)
// - hour_angle: angle to hour position from center
// - rainbow_spread: 0.0 (no spread) to 1.0 (30 degree spread)
// - show_markers: if true, show watch overlay (hour markers)
// - prism_r, prism_g, prism_b: RGB values (0-255) for prism stroke
// - glow_width_percent: prism glow width as fraction of radius
// - glow_intensity: 0.0-1.0 multiplier for prism glow brightness
// - glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - ray_glow_width: glow width for rays in pixels
// - ray_glow_intensity: 0.0-1.0 multiplier for ray glow brightness
// - ray_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - marker_length_percent: how far markers extend towards center (0.0-1.0)
// - marker_glow_width: glow width for markers as fraction of radius
// - marker_glow_intensity: 0.0-1.0 multiplier for marker glow brightness
// - marker_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - grain_intensity: 0.0-1.0 intensity of film grain effect
// - grain_scale: DPR to scale grain size (1.0 = no scaling)
// - grain_prism_only: 1 = only apply grain inside prism
// - gradient_fill: 1 = fill gradient between rainbow rays
// - vignette: 1 = apply vignette effect to background
// - palette: ColorPalette enum value (0-4) for rainbow color scheme
// - reverse_spectrum: 1 = reverse spectral order (album art style: red on top)
static void render_watchface_scene(
  float* float_fb,  // Float buffer for linear rendering
  uint8_t* fb,      // Output buffer (gamma-corrected)
  int width, int height,
  float cx, float cy, float radius,
  float entry_x, float entry_y,
  float hour_angle,
  float rainbow_spread,
  const Prism* prism,
  int show_markers,
  uint8_t prism_r,
  uint8_t prism_g,
  uint8_t prism_b,
  float glow_width_percent,
  float glow_intensity,
  int glow_falloff,
  float ray_glow_width,
  float ray_glow_intensity,
  int ray_glow_falloff,
  float marker_length_percent,
  float marker_glow_width,
  float marker_glow_intensity,
  int marker_glow_falloff,
  float grain_intensity,
  float grain_scale,
  int grain_prism_only,
  int gradient_fill,
  int vignette,
  int palette,
  int reverse_spectrum
) {
  // Initialize precomputed data (reinitializes if palette changed)
  init_band_colors((ColorPalette)palette);

  // Convert prism color from sRGB to linear
  float prism_r_f = srgb_to_linear(prism_r);
  float prism_g_f = srgb_to_linear(prism_g);
  float prism_b_f = srgb_to_linear(prism_b);

  // Initialize background (to float buffer)
  init_watch_framebuffer_f(float_fb, width, height, cx, cy, radius, vignette ? 1.0f : 0.0f, 0);

  // Entry ray direction: toward center
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  // Find where entry ray hits prism
  RayHit prism_entry = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, prism);

  if (!prism_entry.hit) {
    // Ray doesn't hit prism - just draw overlay and return
    draw_prism_glow_f(float_fb, width, height, prism, prism_r_f, prism_g_f, prism_b_f,
                      radius * glow_width_percent, glow_intensity, glow_falloff);
    if (show_markers) {
      draw_watch_overlay_f(float_fb, width, height, cx, cy, radius,
                           marker_length_percent,
                           marker_glow_width, marker_glow_intensity, marker_glow_falloff);
    }
    // Convert float buffer to output buffer with sRGB gamma correction and film grain
    finalize_framebuffer(float_fb, fb, width, height,
                         grain_intensity, grain_scale, cx, cy, radius, vignette,
                         prism, grain_prism_only);
    return;
  }

  // Clipping data for external rays (entry ray and rainbow rays)
  float circle_clip[3] = { cx, cy, radius };

  // Clip incoming ray once (shared by all bands)
  float clip_x0, clip_y0, clip_x1, clip_y1;
  int has_clipped_entry = clip_segment_to_circle(
    entry_x, entry_y, prism_entry.px, prism_entry.py,
    cx, cy, radius,
    &clip_x0, &clip_y0, &clip_x1, &clip_y1
  );

  // Compute bounce decision once using guiding ray (before band loop)
  BounceInfo bounce = compute_bounce_info(
    prism_entry.edge_idx, prism_entry.u,
    hour_angle,
    prism
  );

  // Draw gradient fill between rainbow rays (when enabled and spread > 0)
  if (gradient_fill && rainbow_spread > 0.001f) {
    // Compute boundary angles for the full rainbow (first and last bands)
    float angle_first = compute_exit_angle(hour_angle, rainbow_spread, 0);
    float angle_last = compute_exit_angle(hour_angle, rainbow_spread, NUM_BANDS - 1);

    // Find exit points for boundary rays
    RayHit exit_first = find_prism_exit_from_center(cx, cy, angle_first, prism);
    RayHit exit_last = find_prism_exit_from_center(cx, cy, angle_last, prism);

    if (exit_first.hit && exit_last.hit) {
      float gradient_intensity = 1.0f;

      // For external gradient, compute angles from CENTER to where boundary rays hit CIRCLE
      // (not the ray direction angles, which causes parallax mismatch since rays don't start at center)
      float ext_dir_first_x = cosf_approx(angle_first);
      float ext_dir_first_y = sinf_approx(angle_first);
      float border_first_x, border_first_y;
      ray_circle_intersection(exit_first.px, exit_first.py, ext_dir_first_x, ext_dir_first_y,
                              cx, cy, radius, &border_first_x, &border_first_y);
      float ext_angle_first = atan2_approx(border_first_y - cy, border_first_x - cx);

      float ext_dir_last_x = cosf_approx(angle_last);
      float ext_dir_last_y = sinf_approx(angle_last);
      float border_last_x, border_last_y;
      ray_circle_intersection(exit_last.px, exit_last.py, ext_dir_last_x, ext_dir_last_y,
                              cx, cy, radius, &border_last_x, &border_last_y);
      float ext_angle_last = atan2_approx(border_last_y - cy, border_last_x - cx);

      // Extend gradient angles to include infrared/ultraviolet zones
      // Ray-to-ray spans (N-1)/N of full spread, so extend by 0.5/N on each side
      // This makes full spread = N/(N-1) * ray-to-ray spread
      float ray_span = ext_angle_last - ext_angle_first;
      // Handle angle wrapping
      if (ray_span > PI) ray_span -= 2.0f * PI;
      if (ray_span < -PI) ray_span += 2.0f * PI;
      float edge_margin = ray_span * EDGE_MARGIN_FACTOR;
      float ext_angle_infrared = ext_angle_first - edge_margin;
      float ext_angle_ultraviolet = ext_angle_last + edge_margin;

      // Draw continuous gradient outside prism (uses center as origin)
      draw_gradient_continuous_f(
        float_fb, width, height, GRADIENT_EXTERNAL,
        cx, cy,  // origin = center
        cx, cy, radius,
        ext_angle_infrared, ext_angle_ultraviolet,
        prism, gradient_intensity, reverse_spectrum
      );

      // Draw continuous gradient inside prism
      // Origin point: when bouncing, light spreads from bounce point; otherwise from entry point
      float grad_origin_x = bounce.needs_bounce ? bounce.bounce_x : prism_entry.px;
      float grad_origin_y = bounce.needs_bounce ? bounce.bounce_y : prism_entry.py;

      // Compute internal exit points with perpendicular offsets for gradient boundaries
      float internal_spread = rainbow_spread * INTERNAL_FAN_FACTOR * MAX_SPREAD_RAD;
      float offset_first = 0.5f * internal_spread;   // Red ray side: positive offset
      float offset_last = -0.5f * internal_spread;   // Violet ray side: negative offset

      float internal_exit_first_x = exit_first.px + cosf_approx(angle_first + PI/2) * offset_first * 2.0f;
      float internal_exit_first_y = exit_first.py + sinf_approx(angle_first + PI/2) * offset_first * 2.0f;
      float internal_exit_last_x = exit_last.px + cosf_approx(angle_last + PI/2) * offset_last * 2.0f;
      float internal_exit_last_y = exit_last.py + sinf_approx(angle_last + PI/2) * offset_last * 2.0f;

      // Compute angles from origin to internal exit points (ray positions)
      float internal_angle_first = atan2_approx(internal_exit_first_y - grad_origin_y, internal_exit_first_x - grad_origin_x);
      float internal_angle_last = atan2_approx(internal_exit_last_y - grad_origin_y, internal_exit_last_x - grad_origin_x);

      // Extend internal gradient angles to include infrared/ultraviolet zones
      // Same proportional extension as external gradient
      float internal_ray_span = internal_angle_last - internal_angle_first;
      if (internal_ray_span > PI) internal_ray_span -= 2.0f * PI;
      if (internal_ray_span < -PI) internal_ray_span += 2.0f * PI;
      float internal_edge_margin = internal_ray_span * EDGE_MARGIN_FACTOR;
      float internal_angle_infrared = internal_angle_first - internal_edge_margin;
      float internal_angle_ultraviolet = internal_angle_last + internal_edge_margin;

      draw_gradient_continuous_f(
        float_fb, width, height, GRADIENT_INTERNAL,
        grad_origin_x, grad_origin_y,
        0, 0, 0,  // cx, cy, radius unused for internal mode
        internal_angle_infrared, internal_angle_ultraviolet,
        prism, gradient_intensity, reverse_spectrum
      );
    }
  }

  // Draw all rays per-band for consistent brightness (additive blending)
  // Outside ray: always white (all bands add to white)
  // Internal rays: always use band colors (inner spectrum always on)
  for (int i = 0; i < NUM_BANDS; i++) {
    // When reverse_spectrum is true, reverse the color lookup (album art style)
    int color_idx = reverse_spectrum ? (NUM_BANDS - 1 - i) : i;
    RGB_Linear color = BAND_COLORS_LINEAR[color_idx];

    // Draw incoming ray (outside prism) - pure white
    if (has_clipped_entry) {
      draw_line_with_glow_additive_f(float_fb, width, height,
        clip_x0, clip_y0, clip_x1, clip_y1,
        1.0f, 1.0f, 1.0f, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
        0, circle_clip, prism->vertices);
    }

    // Compute exit angle for this band
    float exit_angle = compute_exit_angle(hour_angle, rainbow_spread, i);

    // Find where exit ray (from center) exits the prism
    RayHit prism_exit = find_prism_exit_from_center(cx, cy, exit_angle, prism);

    if (prism_exit.hit) {
      // Internal path: from entry point to exit point (inside prism)
      // Apply slight internal fan for visual effect
      float internal_t = (float)i / (float)(NUM_BANDS - 1);
      float internal_spread = rainbow_spread * INTERNAL_FAN_FACTOR * MAX_SPREAD_RAD;
      float internal_offset = (0.5f - internal_t) * internal_spread;

      // Adjust internal endpoint slightly based on band
      float internal_exit_x = prism_exit.px + cosf_approx(exit_angle + PI/2) * internal_offset * 2.0f;
      float internal_exit_y = prism_exit.py + sinf_approx(exit_angle + PI/2) * internal_offset * 2.0f;

      if (bounce.needs_bounce) {
        // Entry→bounce segment: pure white (input ray continuation, not dispersion)
        draw_line_with_glow_additive_f(float_fb, width, height,
          prism_entry.px, prism_entry.py,
          bounce.bounce_x, bounce.bounce_y,
          1.0f, 1.0f, 1.0f, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);

        // Bounced path: bounce → exit
        draw_line_with_glow_additive_f(float_fb, width, height,
          bounce.bounce_x, bounce.bounce_y,
          internal_exit_x, internal_exit_y,
          color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);
      } else {
        // Direct path: entry → exit
        draw_line_with_glow_additive_f(float_fb, width, height,
          prism_entry.px, prism_entry.py,
          internal_exit_x, internal_exit_y,
          color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);
      }

      // Draw exit ray (from prism exit to circle edge)
      float exit_dir_x = cosf_approx(exit_angle);
      float exit_dir_y = sinf_approx(exit_angle);

      float border_x, border_y;
      if (ray_circle_intersection(
        prism_exit.px, prism_exit.py,
        exit_dir_x, exit_dir_y,
        cx, cy, radius,
        &border_x, &border_y
      )) {
        float exit_clip_x0, exit_clip_y0, exit_clip_x1, exit_clip_y1;
        if (clip_segment_to_circle(
          prism_exit.px, prism_exit.py, border_x, border_y,
          cx, cy, radius,
          &exit_clip_x0, &exit_clip_y0, &exit_clip_x1, &exit_clip_y1
        )) {
          draw_line_with_glow_additive_f(float_fb, width, height,
            exit_clip_x0, exit_clip_y0, exit_clip_x1, exit_clip_y1,
            color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
            0, circle_clip, prism->vertices);
        }
      }
    }
  }

  // Draw prism with inner glow
  draw_prism_glow_f(float_fb, width, height, prism, prism_r_f, prism_g_f, prism_b_f,
                    radius * glow_width_percent, glow_intensity, glow_falloff);

  // Draw watch overlay (hour markers) if show_markers is set
  if (show_markers) {
    draw_watch_overlay_f(float_fb, width, height, cx, cy, radius,
                         marker_length_percent,
                         marker_glow_width, marker_glow_intensity, marker_glow_falloff);
  }

  // Convert float buffer to output buffer with sRGB gamma correction and film grain
  finalize_framebuffer(float_fb, fb, width, height,
                       grain_intensity, grain_scale, cx, cy, radius, vignette,
                       prism, grain_prism_only);
}
