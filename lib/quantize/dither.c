#include "quantize/dither.h"
#include "fastmath.h"
#include <stddef.h>

// Round non-negative float to uint8_t (assumes f >= 0)
// NOLINTNEXTLINE(bugprone-incorrect-roundings)
static inline uint8_t round_f_to_u8(float f) { return (uint8_t)(f + 0.5f); }

#ifndef NULL
#define NULL ((void *)0)
#endif

// =================================================================================================
// Palette Definitions
// =================================================================================================

// Pure RGB palette for dithering (ideal target colors)
const DitherRGB DITHER_PALETTE_IDEAL[DITHER_PALETTE_IDEAL_COUNT] = {
    {0, 0, 0},       // 0: Black
    {255, 255, 255}, // 1: White
    {255, 255, 0},   // 2: Yellow
    {255, 0, 0},     // 3: Red
    {0, 0, 255},     // 4: Blue
    {0, 255, 0},     // 5: Green
};

// Inky Impression 13.3" device palette (Spectra 6)
const DitherRGB DITHER_PALETTE_DEVICE[DITHER_PALETTE_DEVICE_COUNT] = {
    {0, 0, 0},       // 0: Black
    {161, 164, 165}, // 1: Gray (device white appears grayish)
    {208, 190, 71},  // 2: Gold/Yellow
    {156, 72, 75},   // 3: Burgundy/Red
    {61, 59, 94},    // 4: Dark Blue
    {58, 91, 70},    // 5: Forest Green
};

// Measured Spectra 6 palette (from epdoptimize)
const DitherRGB DITHER_PALETTE_SPECTRA6[DITHER_PALETTE_SPECTRA6_COUNT] = {
    {25, 30, 33},    // 0: Black (#191E21)
    {232, 232, 232}, // 1: White (#e8e8e8)
    {239, 222, 68},  // 2: Yellow (#efde44)
    {178, 19, 24},   // 3: Red (#b21318)
    {33, 87, 186},   // 4: Blue (#2157ba)
    {18, 95, 32},    // 5: Green (#125f20)
};

// =================================================================================================
// Constants
// =================================================================================================

// Large float value for distance initialization
#define MAX_DISTANCE 3.4e38f

// =================================================================================================
// Color Space Conversions
// =================================================================================================

// Convert sRGB (0-255) to linear (0.0-1.0)
float dither_srgb_to_linear(uint8_t srgb) {
  float s = (float)srgb / 255.0f;
  if (s <= 0.04045f) {
    return s / 12.92f;
  }
  return fast_powf((s + 0.055f) / 1.055f, 2.4f);
}

// Convert linear RGB to OkLab
DitherOkLab dither_linear_to_oklab(float r, float g, float b) {
  // Linear RGB to LMS (cone responses)
  float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
  float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
  float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;

  // Cube root (perceptual nonlinearity)
  float lp = cbrtf_impl(l);
  float mp = cbrtf_impl(m);
  float sp = cbrtf_impl(s);

  // LMS' to OkLab
  DitherOkLab lab;
  lab.L = 0.2104542553f * lp + 0.7936177850f * mp - 0.0040720468f * sp;
  lab.a = 1.9779984951f * lp - 2.4285922050f * mp + 0.4505937099f * sp;
  lab.b = 0.0259040371f * lp + 0.7827717662f * mp - 0.8086757660f * sp;
  return lab;
}

// =================================================================================================
// OkLab Distance Functions
// =================================================================================================

// Compute OkLab chroma (saturation metric)
float dither_oklab_chroma(DitherOkLab color) {
  return sqrtf_impl(color.a * color.a + color.b * color.b);
}

// OkLab weighted distance squared
// chroma_weight = 1.0: L weighted 2x (default, good for general images)
// chroma_weight = 2.0: Equal L and chroma weighting (better for rainbows)
// chroma_weight = 4.0: Chroma weighted 2x (strongly prioritizes hue matching)
float dither_oklab_distance_sq(DitherOkLab a, DitherOkLab b, float chroma_weight) {
  float d_l = a.L - b.L;
  float da = a.a - b.a;
  float db = a.b - b.b;
  // Clamp to valid range (0.5-4.0) to avoid division issues
  float cw = clampf(chroma_weight, 0.5f, 4.0f);
  // Inverse relationship: as chroma_weight increases, l_weight decreases
  float l_weight = 2.0f / cw;
  return l_weight * d_l * d_l + cw * (da * da + db * db);
}

// Find closest palette color index using OkLab distance
int dither_find_closest_color(DitherOkLab color, const DitherOkLab *palette, int palette_count,
                              float chroma_weight) {
  int best_idx = 0;
  float best_dist = MAX_DISTANCE;

  for (int i = 0; i < palette_count; i++) {
    float dist = dither_oklab_distance_sq(color, palette[i], chroma_weight);
    if (dist < best_dist) {
      best_dist = dist;
      best_idx = i;
    }
  }

  return best_idx;
}

// Find closest B/W color index from two specified palette indices
int dither_find_closest_bw(DitherOkLab color, const DitherOkLab *palette, int black_idx,
                           int white_idx, float chroma_weight) {
  float dist_black = dither_oklab_distance_sq(color, palette[black_idx], chroma_weight);
  float dist_white = dither_oklab_distance_sq(color, palette[white_idx], chroma_weight);
  return (dist_black < dist_white) ? black_idx : white_idx;
}

// Find closest color with B/W threshold for grayscale regions
static int find_color_with_bw_threshold(DitherOkLab color, const DitherOkLab *palette,
                                        int palette_count, float bw_threshold, int bw_black_idx,
                                        int bw_white_idx, float chroma_weight) {
  if (bw_threshold > 0.0f && dither_oklab_chroma(color) < bw_threshold) {
    return dither_find_closest_bw(color, palette, bw_black_idx, bw_white_idx, chroma_weight);
  }
  return dither_find_closest_color(color, palette, palette_count, chroma_weight);
}

// =================================================================================================
// Cache Management
// =================================================================================================

// Initialize the cache for a given palette
int quantize_dither_init_cache(DitherCache *cache, const DitherRGB *palette, int palette_count) {
  if (!cache || !palette || palette_count <= 0)
    return -1;
  if (palette_count > cache->palette_capacity)
    return -1;

  // Check if we can skip recomputation (same palette pointer and count)
  if (cache->last_palette == palette && cache->last_palette_count == palette_count) {
    return 0; // Cache is still valid
  }

  // Convert palette to OkLab and linear RGB
  for (int i = 0; i < palette_count; i++) {
    float r = dither_srgb_to_linear(palette[i].r);
    float g = dither_srgb_to_linear(palette[i].g);
    float b = dither_srgb_to_linear(palette[i].b);
    cache->palette_linear[i] = (DitherLinearRGB){r, g, b};
    cache->palette_oklab[i] = dither_linear_to_oklab(r, g, b);
  }

  cache->last_palette = palette;
  cache->last_palette_count = palette_count;
  return 0;
}

// =================================================================================================
// Error Buffer Access Helpers
// =================================================================================================
// Error buffer layout: 3 rows × 3 channels, each row has 'width' elements
// Total size: width * 9 floats
// Index: row * width * 3 + channel * width + x
//   where row = 0,1,2 and channel = 0(r),1(g),2(b)

static inline float *err_row(float *buf, int width, int row, int channel) {
  return buf + (size_t)row * (size_t)width * 3 + (size_t)channel * (size_t)width;
}

// =================================================================================================
// Atkinson Error Diffusion
// =================================================================================================
// Diffuses only 75% of quantization error, creating higher contrast.
// Pattern (each neighbor receives 1/8 of error):
//       *   1   1
//   1   1   1
//       1

static void dither_atkinson(const float *float_fb, uint8_t *out_fb, int width, int height,
                            DitherCache *cache, const DitherConfig *config) {
  const DitherRGB *palette = config->palette;
  int palette_count = config->palette_count;
  int preserve_alpha = config->preserve_alpha;
  float strength = config->strength;
  int oklab_error = config->oklab_error;
  float bw_threshold = config->bw_threshold;
  int bw_black_idx = config->bw_black_idx;
  int bw_white_idx = config->bw_white_idx;
  float chroma_weight = config->chroma_weight;

  // Atkinson diffuses 1/8 to each of 6 neighbors (75% total)
  float d = 0.125f * strength;

  float *err = cache->err_buffer;

  // Get row pointers for each channel
  float *err_curr_r = err_row(err, width, 0, 0);
  float *err_curr_g = err_row(err, width, 0, 1);
  float *err_curr_b = err_row(err, width, 0, 2);
  float *err_next1_r = err_row(err, width, 1, 0);
  float *err_next1_g = err_row(err, width, 1, 1);
  float *err_next1_b = err_row(err, width, 1, 2);
  float *err_next2_r = err_row(err, width, 2, 0);
  float *err_next2_g = err_row(err, width, 2, 1);
  float *err_next2_b = err_row(err, width, 2, 2);

  // Clear error buffers
  for (int i = 0; i < width; i++) {
    err_curr_r[i] = err_curr_g[i] = err_curr_b[i] = 0.0f;
    err_next1_r[i] = err_next1_g[i] = err_next1_b[i] = 0.0f;
    err_next2_r[i] = err_next2_g[i] = err_next2_b[i] = 0.0f;
  }

  for (int y = 0; y < height; y++) {
    // Serpentine scan: alternate direction each row
    int left_to_right = (y % 2 == 0);
    int x_start = left_to_right ? 0 : width - 1;
    int x_end = left_to_right ? width : -1;
    int x_step = left_to_right ? 1 : -1;

    for (int x = x_start; x != x_end; x += x_step) {
      int i = (y * width + x) * 4;
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      DitherOkLab color;
      int idx;

      if (oklab_error) {
        // OkLab error diffusion
        float r = clampf(float_fb[i], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
        color = dither_linear_to_oklab(r, g, b);

        // Add accumulated OkLab error
        color.L = clampf(color.L + err_curr_r[x], 0.0f, 1.0f);
        color.a = color.a + err_curr_g[x];
        color.b = color.b + err_curr_b[x];

        idx = find_color_with_bw_threshold(color, cache->palette_oklab, palette_count, bw_threshold,
                                           bw_black_idx, bw_white_idx, chroma_weight);

        // Calculate quantization error in OkLab space
        DitherOkLab quantized = cache->palette_oklab[idx];
        float err_l = (color.L - quantized.L) * d;
        float err_a = (color.a - quantized.a) * d;
        float err_b = (color.b - quantized.b) * d;

        // Diffuse error
        int fwd1 = x + x_step;
        int fwd2 = x + 2 * x_step;
        int back1 = x - x_step;

        // Current row: fwd1, fwd2
        if (fwd1 >= 0 && fwd1 < width) {
          err_curr_r[fwd1] += err_l;
          err_curr_g[fwd1] += err_a;
          err_curr_b[fwd1] += err_b;
        }
        if (fwd2 >= 0 && fwd2 < width) {
          err_curr_r[fwd2] += err_l;
          err_curr_g[fwd2] += err_a;
          err_curr_b[fwd2] += err_b;
        }
        // Next row (y+1): back1, x, fwd1
        if (back1 >= 0 && back1 < width) {
          err_next1_r[back1] += err_l;
          err_next1_g[back1] += err_a;
          err_next1_b[back1] += err_b;
        }
        err_next1_r[x] += err_l;
        err_next1_g[x] += err_a;
        err_next1_b[x] += err_b;
        if (fwd1 >= 0 && fwd1 < width) {
          err_next1_r[fwd1] += err_l;
          err_next1_g[fwd1] += err_a;
          err_next1_b[fwd1] += err_b;
        }
        // Row after next (y+2): x only
        err_next2_r[x] += err_l;
        err_next2_g[x] += err_a;
        err_next2_b[x] += err_b;
      } else {
        // Linear RGB error diffusion
        float r = clampf(float_fb[i] + err_curr_r[x], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1] + err_curr_g[x], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2] + err_curr_b[x], 0.0f, 1.0f);

        color = dither_linear_to_oklab(r, g, b);
        idx = find_color_with_bw_threshold(color, cache->palette_oklab, palette_count, bw_threshold,
                                           bw_black_idx, bw_white_idx, chroma_weight);

        // Calculate quantization error in linear RGB
        DitherLinearRGB quantized = cache->palette_linear[idx];
        float err_r = (r - quantized.r) * d;
        float err_g = (g - quantized.g) * d;
        float err_b = (b - quantized.b) * d;

        // Diffuse error
        int fwd1 = x + x_step;
        int fwd2 = x + 2 * x_step;
        int back1 = x - x_step;

        // Current row: fwd1, fwd2
        if (fwd1 >= 0 && fwd1 < width) {
          err_curr_r[fwd1] += err_r;
          err_curr_g[fwd1] += err_g;
          err_curr_b[fwd1] += err_b;
        }
        if (fwd2 >= 0 && fwd2 < width) {
          err_curr_r[fwd2] += err_r;
          err_curr_g[fwd2] += err_g;
          err_curr_b[fwd2] += err_b;
        }
        // Next row (y+1): back1, x, fwd1
        if (back1 >= 0 && back1 < width) {
          err_next1_r[back1] += err_r;
          err_next1_g[back1] += err_g;
          err_next1_b[back1] += err_b;
        }
        err_next1_r[x] += err_r;
        err_next1_g[x] += err_g;
        err_next1_b[x] += err_b;
        if (fwd1 >= 0 && fwd1 < width) {
          err_next1_r[fwd1] += err_r;
          err_next1_g[fwd1] += err_g;
          err_next1_b[fwd1] += err_b;
        }
        // Row after next (y+2): x only
        err_next2_r[x] += err_r;
        err_next2_g[x] += err_g;
        err_next2_b[x] += err_b;
      }

      // Output the quantized color
      out_fb[i] = palette[idx].r;
      out_fb[i + 1] = palette[idx].g;
      out_fb[i + 2] = palette[idx].b;
      out_fb[i + 3] = preserve_alpha ? round_f_to_u8(a * 255.0f) : 255;
    }

    // Rotate row buffers
    for (int i = 0; i < width; i++) {
      err_curr_r[i] = err_next1_r[i];
      err_curr_g[i] = err_next1_g[i];
      err_curr_b[i] = err_next1_b[i];
      err_next1_r[i] = err_next2_r[i];
      err_next1_g[i] = err_next2_g[i];
      err_next1_b[i] = err_next2_b[i];
      err_next2_r[i] = err_next2_g[i] = err_next2_b[i] = 0.0f;
    }
  }
}

// =================================================================================================
// Floyd-Steinberg Error Diffusion
// =================================================================================================
// Diffuses 100% of quantization error, producing smoother gradients.
// Pattern:
//       X   7/16
//   3/16  5/16  1/16

static void dither_floyd_steinberg(const float *float_fb, uint8_t *out_fb, int width, int height,
                                   DitherCache *cache, const DitherConfig *config) {
  const DitherRGB *palette = config->palette;
  int palette_count = config->palette_count;
  int preserve_alpha = config->preserve_alpha;
  float strength = config->strength;
  int oklab_error = config->oklab_error;
  float bw_threshold = config->bw_threshold;
  int bw_black_idx = config->bw_black_idx;
  int bw_white_idx = config->bw_white_idx;
  float chroma_weight = config->chroma_weight;

  // Floyd-Steinberg weights scaled by strength
  float d7 = (7.0f / 16.0f) * strength;
  float d3 = (3.0f / 16.0f) * strength;
  float d5 = (5.0f / 16.0f) * strength;
  float d1 = (1.0f / 16.0f) * strength;

  float *err = cache->err_buffer;

  // Get row pointers (FS only needs 2 rows, but we use same buffer layout)
  float *err_curr_r = err_row(err, width, 0, 0);
  float *err_curr_g = err_row(err, width, 0, 1);
  float *err_curr_b = err_row(err, width, 0, 2);
  float *err_next1_r = err_row(err, width, 1, 0);
  float *err_next1_g = err_row(err, width, 1, 1);
  float *err_next1_b = err_row(err, width, 1, 2);

  // Clear error buffers (FS only needs 2 rows)
  for (int i = 0; i < width; i++) {
    err_curr_r[i] = err_curr_g[i] = err_curr_b[i] = 0.0f;
    err_next1_r[i] = err_next1_g[i] = err_next1_b[i] = 0.0f;
  }

  for (int y = 0; y < height; y++) {
    // Serpentine scan
    int left_to_right = (y % 2 == 0);
    int x_start = left_to_right ? 0 : width - 1;
    int x_end = left_to_right ? width : -1;
    int x_step = left_to_right ? 1 : -1;

    for (int x = x_start; x != x_end; x += x_step) {
      int i = (y * width + x) * 4;
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      DitherOkLab color;
      int idx;
      float err_1, err_2, err_3;

      if (oklab_error) {
        // OkLab error diffusion
        float r = clampf(float_fb[i], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
        color = dither_linear_to_oklab(r, g, b);

        // Add accumulated OkLab error
        color.L = clampf(color.L + err_curr_r[x], 0.0f, 1.0f);
        color.a = color.a + err_curr_g[x];
        color.b = color.b + err_curr_b[x];

        idx = find_color_with_bw_threshold(color, cache->palette_oklab, palette_count, bw_threshold,
                                           bw_black_idx, bw_white_idx, chroma_weight);

        // Calculate quantization error in OkLab space
        DitherOkLab quantized = cache->palette_oklab[idx];
        err_1 = color.L - quantized.L;
        err_2 = color.a - quantized.a;
        err_3 = color.b - quantized.b;
      } else {
        // Linear RGB error diffusion
        float r = clampf(float_fb[i] + err_curr_r[x], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1] + err_curr_g[x], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2] + err_curr_b[x], 0.0f, 1.0f);

        color = dither_linear_to_oklab(r, g, b);
        idx = find_color_with_bw_threshold(color, cache->palette_oklab, palette_count, bw_threshold,
                                           bw_black_idx, bw_white_idx, chroma_weight);

        // Calculate quantization error in linear RGB
        DitherLinearRGB quantized = cache->palette_linear[idx];
        err_1 = r - quantized.r;
        err_2 = g - quantized.g;
        err_3 = b - quantized.b;
      }

      // Output the quantized color
      out_fb[i] = palette[idx].r;
      out_fb[i + 1] = palette[idx].g;
      out_fb[i + 2] = palette[idx].b;
      out_fb[i + 3] = preserve_alpha ? round_f_to_u8(a * 255.0f) : 255;

      // Distribute error
      int fwd = x + x_step;
      int back = x - x_step;

      // Current row: forward pixel gets 7/16
      if (fwd >= 0 && fwd < width) {
        err_curr_r[fwd] += err_1 * d7;
        err_curr_g[fwd] += err_2 * d7;
        err_curr_b[fwd] += err_3 * d7;
      }

      // Next row: back gets 3/16, same x gets 5/16, forward gets 1/16
      if (back >= 0 && back < width) {
        err_next1_r[back] += err_1 * d3;
        err_next1_g[back] += err_2 * d3;
        err_next1_b[back] += err_3 * d3;
      }
      err_next1_r[x] += err_1 * d5;
      err_next1_g[x] += err_2 * d5;
      err_next1_b[x] += err_3 * d5;
      if (fwd >= 0 && fwd < width) {
        err_next1_r[fwd] += err_1 * d1;
        err_next1_g[fwd] += err_2 * d1;
        err_next1_b[fwd] += err_3 * d1;
      }
    }

    // Rotate row buffers
    for (int i = 0; i < width; i++) {
      err_curr_r[i] = err_next1_r[i];
      err_curr_g[i] = err_next1_g[i];
      err_curr_b[i] = err_next1_b[i];
      err_next1_r[i] = err_next1_g[i] = err_next1_b[i] = 0.0f;
    }
  }
}

// =================================================================================================
// Main Quantizer Function
// =================================================================================================

int quantize_dither_apply(const float *float_fb, uint8_t *out_fb, int width, int height,
                          const DitherConfig *config, DitherCache *cache) {
  // Validate inputs
  if (!float_fb || !out_fb || !config || !cache)
    return -1;
  if (!config->palette || config->palette_count <= 0)
    return -1;
  if (width <= 0 || height <= 0)
    return -1;
  if (width > cache->err_row_width)
    return -1;
  if (config->palette_count > cache->palette_capacity)
    return -1;

  // Initialize cache if palette changed
  if (quantize_dither_init_cache(cache, config->palette, config->palette_count) != 0) {
    return -1;
  }

  // Dispatch to appropriate algorithm
  switch (config->algorithm) {
  case DITHER_FLOYD_STEINBERG:
    dither_floyd_steinberg(float_fb, out_fb, width, height, cache, config);
    break;
  case DITHER_ATKINSON:
  default:
    dither_atkinson(float_fb, out_fb, width, height, cache, config);
    break;
  }

  return 0;
}
