#pragma once

#include "color.h"

// =================================================================================================
// Dither Palette for 6-Color E-Ink Displays
// =================================================================================================
// Pure RGB palette used for dithering calculations. These are the ideal target colors
// that provide maximum color separation for quantization.

typedef struct {
  uint8_t r, g, b;
} DitherRGB;

// Palette mode enum
typedef enum {
  DITHER_PALETTE_IDEAL = 0,   // Pure RGB colors (ideal for quantization)
  DITHER_PALETTE_DEVICE = 1,  // Inky Impression 13.3" device colors
  DITHER_PALETTE_BLEND = 2    // Interpolated between IDEAL and DEVICE
} DitherPaletteMode;

// Dither kernel enum
typedef enum {
  DITHER_KERNEL_ATKINSON = 0,       // Atkinson: diffuses 75% of error, higher contrast
  DITHER_KERNEL_FLOYD_STEINBERG = 1 // Floyd-Steinberg: diffuses 100%, smoother gradients
} DitherKernel;

// Pure RGB palette for dithering (6 colors)
// These are the ideal target colors for color quantization
static const DitherRGB DITHER_PALETTE[6] = {
    {0, 0, 0},       // 0: Black
    {255, 255, 255}, // 1: White
    {255, 255, 0},   // 2: Yellow
    {255, 0, 0},     // 3: Red
    {0, 0, 255},     // 4: Blue
    {0, 255, 0},     // 5: Green
};

// =================================================================================================
// Inky Impression 13.3" Device Palette (Spectra 6)
// =================================================================================================
// Measured/calibrated colors that approximate what the e-ink display actually produces.
// Use this palette for previewing how the image will appear on the physical device.

static const DitherRGB INKY_DEVICE_PALETTE[6] = {
    {0, 0, 0},       // 0: Black
    {161, 164, 165}, // 1: Gray (device white appears grayish)
    {208, 190, 71},  // 2: Gold/Yellow
    {156, 72, 75},   // 3: Burgundy/Red
    {61, 59, 94},    // 4: Dark Blue
    {58, 91, 70},    // 5: Forest Green
};

#define DITHER_PALETTE_SIZE 6

// =================================================================================================
// Blended Palette (computed at runtime when mode=BLEND)
// =================================================================================================

static DitherRGB DITHER_BLENDED_PALETTE[6];
static float dither_blend_saturation = -1.0f;  // Track current blend value for cache invalidation

// =================================================================================================
// Pre-computed Palette Data (OkLab for matching, Linear RGB for error diffusion)
// =================================================================================================

typedef struct {
  float r, g, b;
} LinearRGB;

static OkLab DITHER_PALETTE_OKLAB[DITHER_PALETTE_SIZE];
static LinearRGB DITHER_PALETTE_LINEAR[DITHER_PALETTE_SIZE];

// Cache keys for init_dither_palette - tracks palette pointer, mode, and saturation
// to correctly invalidate when BLEND mode saturation changes
static const DitherRGB* dither_initialized_palette = 0;
static DitherPaletteMode dither_initialized_mode = (DitherPaletteMode)-1;
static float dither_initialized_saturation = -1.0f;

// Compute blended palette: blended[i].c = round((1-s)*IDEAL[i].c + s*DEVICE[i].c)
// s=0 → identical to IDEAL, s=1 → identical to DEVICE
static inline void compute_blended_palette(float saturation) {
  float s = clampf(saturation, 0.0f, 1.0f);
  float inv_s = 1.0f - s;

  for (int i = 0; i < DITHER_PALETTE_SIZE; i++) {
    DITHER_BLENDED_PALETTE[i].r = (uint8_t)(inv_s * DITHER_PALETTE[i].r + s * INKY_DEVICE_PALETTE[i].r + 0.5f);
    DITHER_BLENDED_PALETTE[i].g = (uint8_t)(inv_s * DITHER_PALETTE[i].g + s * INKY_DEVICE_PALETTE[i].g + 0.5f);
    DITHER_BLENDED_PALETTE[i].b = (uint8_t)(inv_s * DITHER_PALETTE[i].b + s * INKY_DEVICE_PALETTE[i].b + 0.5f);
  }

  dither_blend_saturation = s;
}

// Epsilon for float comparison (avoids spurious recomputes from slider jitter)
#define DITHER_SATURATION_EPSILON 1e-5f

// Large float value for distance initialization (approximates FLT_MAX without stdlib)
#define DITHER_MAX_DISTANCE 3.4e38f

// Get the appropriate palette based on mode and saturation.
// For BLEND mode, computes the blended palette if saturation changed.
static inline const DitherRGB* get_dither_palette(DitherPaletteMode palette_mode, float saturation) {
  switch (palette_mode) {
    case DITHER_PALETTE_DEVICE:
      return INKY_DEVICE_PALETTE;
    case DITHER_PALETTE_BLEND: {
      float clamped_sat = clampf(saturation, 0.0f, 1.0f);
      float diff = dither_blend_saturation - clamped_sat;
      if (diff < -DITHER_SATURATION_EPSILON || diff > DITHER_SATURATION_EPSILON) {
        compute_blended_palette(clamped_sat);
      }
      return DITHER_BLENDED_PALETTE;
    }
    case DITHER_PALETTE_IDEAL:
    default:
      return DITHER_PALETTE;
  }
}

// Initialize OkLab and linear RGB representations for a given palette.
// Matching and error diffusion will use this palette. Re-initializes if
// palette, mode, or saturation (for BLEND) changes.
static inline void init_dither_palette(const DitherRGB* palette,
                                       DitherPaletteMode mode,
                                       float saturation) {
  // Check if we can skip recomputation
  if (dither_initialized_palette == palette && dither_initialized_mode == mode) {
    // For BLEND mode, also check if saturation changed significantly
    if (mode != DITHER_PALETTE_BLEND) {
      return;  // Non-blend mode with same palette pointer - no change
    }
    float diff = saturation - dither_initialized_saturation;
    if (diff > -DITHER_SATURATION_EPSILON && diff < DITHER_SATURATION_EPSILON) {
      return;  // BLEND mode with same saturation - no change
    }
  }

  for (int i = 0; i < DITHER_PALETTE_SIZE; i++) {
    // Convert sRGB palette to linear RGB
    float r = srgb_to_linear(palette[i].r);
    float g = srgb_to_linear(palette[i].g);
    float b = srgb_to_linear(palette[i].b);
    DITHER_PALETTE_LINEAR[i] = (LinearRGB){r, g, b};
    DITHER_PALETTE_OKLAB[i] = linear_to_oklab(r, g, b);
  }

  dither_initialized_palette = palette;
  dither_initialized_mode = mode;
  dither_initialized_saturation = saturation;
}

// =================================================================================================
// Atkinson Error Diffusion Dithering
// =================================================================================================
//
// Atkinson dithering (Bill Atkinson, 1984) diffuses only 6/8 (75%) of quantization error,
// creating higher contrast and better detail preservation than Floyd-Steinberg.
//
// Diffusion pattern (each neighbor receives 1/8 of error):
//
//         *   1   1
//     1   1   1
//         1
//
// Where * is current pixel. Only 75% of error is diffused, 25% is discarded.

// =================================================================================================
// Color Distance (Euclidean in OkLab - Perceptually Uniform)
// =================================================================================================

// OkLab weighted distance - L is weighted higher to reduce hue-flipping artifacts.
// With only 6 saturated palette colors, unweighted Euclidean distance can jump
// between colors of similar lightness but different hue (e.g., red/yellow/white).
// Weighting L 2x penalizes lightness jumps, producing smoother gradients.
static inline float oklab_distance_sq(OkLab a, OkLab b) {
  float dL = a.L - b.L;
  float da = a.a - b.a;
  float db = a.b - b.b;
  return 2.0f * dL * dL + da * da + db * db;
}

// =================================================================================================
// Find Closest Palette Color (in OkLab space)
// =================================================================================================

// Find the index of the closest color in the palette using OkLab distance
// Input: OkLab color to match
// Returns: palette index of perceptually closest color
// Note: Caller must call init_dither_palette() first
static inline int find_closest_palette_color_oklab(OkLab color) {
  int best_idx = 0;
  float best_dist = DITHER_MAX_DISTANCE;

  for (int i = 0; i < DITHER_PALETTE_SIZE; i++) {
    float dist = oklab_distance_sq(color, DITHER_PALETTE_OKLAB[i]);
    if (dist < best_dist) {
      best_dist = dist;
      best_idx = i;
    }
  }

  return best_idx;
}

// =================================================================================================
// Atkinson Dithered Color Quantization
// =================================================================================================
// Uses OkLab for perceptually accurate palette matching. Error can be diffused in either
// linear RGB (more stable) or OkLab space (more perceptually uniform gradients).

// Maximum supported width for error diffusion buffers
#define DITHER_MAX_WIDTH 5120

// Three row buffers for error diffusion (Atkinson spreads error 2 rows down)
// Used for either linear RGB (r,g,b) or OkLab (L,a,b) depending on oklab_error mode
static float err_curr_r[DITHER_MAX_WIDTH], err_curr_g[DITHER_MAX_WIDTH], err_curr_b[DITHER_MAX_WIDTH];
static float err_next1_r[DITHER_MAX_WIDTH], err_next1_g[DITHER_MAX_WIDTH], err_next1_b[DITHER_MAX_WIDTH];
static float err_next2_r[DITHER_MAX_WIDTH], err_next2_g[DITHER_MAX_WIDTH], err_next2_b[DITHER_MAX_WIDTH];

// Apply Atkinson error diffusion dithering to an entire buffer.
// Uses OkLab for palette matching. Error diffusion can be in linear RGB or OkLab space.
//
// Parameters:
//   float_fb: Input framebuffer in LINEAR RGB space (RGBA, 0.0-1.0)
//   out_fb: Output framebuffer in sRGB space (RGBA, 0-255)
//   width, height: Image dimensions (width must be <= DITHER_MAX_WIDTH)
//   palette_mode: DITHER_PALETTE_IDEAL, DITHER_PALETTE_DEVICE, or DITHER_PALETTE_BLEND
//   saturation: 0.0-1.0, blend factor (only used when palette_mode=BLEND)
//   preserve_alpha: 1 = preserve alpha from float_fb, 0 = always opaque
//   strength: 0.0-1.0, scales error diffusion (1.0 = full Atkinson 75%, 0.0 = no diffusion)
//   oklab_error: 0 = diffuse error in linear RGB, 1 = diffuse error in OkLab space
//
static inline void dither_buffer_atkinson(
    const float* float_fb, uint8_t* out_fb,
    int width, int height,
    DitherPaletteMode palette_mode, float saturation, int preserve_alpha,
    float strength, int oklab_error) {

  if (width > DITHER_MAX_WIDTH) return;

  // Clamp saturation once and use consistently for caching
  float sat = clampf(saturation, 0.0f, 1.0f);

  // Get the appropriate palette based on mode - used end-to-end for matching and output
  const DitherRGB* palette = get_dither_palette(palette_mode, sat);
  init_dither_palette(palette, palette_mode, sat);

  // Atkinson diffuses 1/8 to each of 6 neighbors (75% total)
  // Scale by user strength: 0.0 = no diffusion, 1.0 = full Atkinson
  float d = 0.125f * strength;

  // Clear error buffers
  for (int i = 0; i < width; i++) {
    err_curr_r[i] = err_curr_g[i] = err_curr_b[i] = 0.0f;
    err_next1_r[i] = err_next1_g[i] = err_next1_b[i] = 0.0f;
    err_next2_r[i] = err_next2_g[i] = err_next2_b[i] = 0.0f;
  }

  for (int y = 0; y < height; y++) {
    // Serpentine scan: alternate direction each row to reduce directional artifacts
    int left_to_right = (y % 2 == 0);
    int x_start = left_to_right ? 0 : width - 1;
    int x_end = left_to_right ? width : -1;
    int x_step = left_to_right ? 1 : -1;

    for (int x = x_start; x != x_end; x += x_step) {
      int i = (y * width + x) * 4;
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      OkLab color;
      int idx;

      if (oklab_error) {
        // OkLab error diffusion: add accumulated error in OkLab space
        float r = clampf(float_fb[i], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
        color = linear_to_oklab(r, g, b);

        // Add accumulated OkLab error (buffers hold L, a, b)
        color.L = clampf(color.L + err_curr_r[x], 0.0f, 1.0f);
        color.a = color.a + err_curr_g[x];  // a/b can be negative, don't clamp to 0
        color.b = color.b + err_curr_b[x];

        idx = find_closest_palette_color_oklab(color);

        // Calculate quantization error in OkLab space
        OkLab quantized = DITHER_PALETTE_OKLAB[idx];
        float err_L = (color.L - quantized.L) * d;
        float err_a = (color.a - quantized.a) * d;
        float err_b = (color.b - quantized.b) * d;

        // Diffuse error (reusing r/g/b buffers for L/a/b)
        int fwd1 = x + x_step;
        int fwd2 = x + 2 * x_step;
        int back1 = x - x_step;

        // Current row: fwd1, fwd2
        if (fwd1 >= 0 && fwd1 < width) {
          err_curr_r[fwd1] += err_L; err_curr_g[fwd1] += err_a; err_curr_b[fwd1] += err_b;
        }
        if (fwd2 >= 0 && fwd2 < width) {
          err_curr_r[fwd2] += err_L; err_curr_g[fwd2] += err_a; err_curr_b[fwd2] += err_b;
        }
        // Next row (y+1): back1, x, fwd1
        if (back1 >= 0 && back1 < width) {
          err_next1_r[back1] += err_L; err_next1_g[back1] += err_a; err_next1_b[back1] += err_b;
        }
        err_next1_r[x] += err_L; err_next1_g[x] += err_a; err_next1_b[x] += err_b;
        if (fwd1 >= 0 && fwd1 < width) {
          err_next1_r[fwd1] += err_L; err_next1_g[fwd1] += err_a; err_next1_b[fwd1] += err_b;
        }
        // Row after next (y+2): x only
        err_next2_r[x] += err_L; err_next2_g[x] += err_a; err_next2_b[x] += err_b;
      } else {
        // Linear RGB error diffusion (original behavior)
        float r = clampf(float_fb[i] + err_curr_r[x], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1] + err_curr_g[x], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2] + err_curr_b[x], 0.0f, 1.0f);

        color = linear_to_oklab(r, g, b);
        idx = find_closest_palette_color_oklab(color);

        // Calculate quantization error in linear RGB
        LinearRGB quantized = DITHER_PALETTE_LINEAR[idx];
        float err_r = (r - quantized.r) * d;
        float err_g = (g - quantized.g) * d;
        float err_b = (b - quantized.b) * d;

        // Diffuse error
        int fwd1 = x + x_step;
        int fwd2 = x + 2 * x_step;
        int back1 = x - x_step;

        // Current row: fwd1, fwd2
        if (fwd1 >= 0 && fwd1 < width) {
          err_curr_r[fwd1] += err_r; err_curr_g[fwd1] += err_g; err_curr_b[fwd1] += err_b;
        }
        if (fwd2 >= 0 && fwd2 < width) {
          err_curr_r[fwd2] += err_r; err_curr_g[fwd2] += err_g; err_curr_b[fwd2] += err_b;
        }
        // Next row (y+1): back1, x, fwd1
        if (back1 >= 0 && back1 < width) {
          err_next1_r[back1] += err_r; err_next1_g[back1] += err_g; err_next1_b[back1] += err_b;
        }
        err_next1_r[x] += err_r; err_next1_g[x] += err_g; err_next1_b[x] += err_b;
        if (fwd1 >= 0 && fwd1 < width) {
          err_next1_r[fwd1] += err_r; err_next1_g[fwd1] += err_g; err_next1_b[fwd1] += err_b;
        }
        // Row after next (y+2): x only
        err_next2_r[x] += err_r; err_next2_g[x] += err_g; err_next2_b[x] += err_b;
      }

      // Output the quantized color
      out_fb[i] = palette[idx].r;
      out_fb[i + 1] = palette[idx].g;
      out_fb[i + 2] = palette[idx].b;
      out_fb[i + 3] = preserve_alpha ? (uint8_t)(a * 255.0f + 0.5f) : 255;
    }

    // Rotate row buffers: next1 becomes current, next2 becomes next1, clear next2
    for (int i = 0; i < width; i++) {
      err_curr_r[i] = err_next1_r[i]; err_curr_g[i] = err_next1_g[i]; err_curr_b[i] = err_next1_b[i];
      err_next1_r[i] = err_next2_r[i]; err_next1_g[i] = err_next2_g[i]; err_next1_b[i] = err_next2_b[i];
      err_next2_r[i] = err_next2_g[i] = err_next2_b[i] = 0.0f;
    }
  }
}

// =================================================================================================
// Floyd-Steinberg Error Diffusion Dithering
// =================================================================================================
//
// Floyd-Steinberg dithering (1976) diffuses 100% of quantization error, producing smoother
// gradients but potentially more "wormy" artifacts in some patterns compared to Atkinson.
//
// Diffusion pattern (serpentine mirrored):
//
// Left-to-right:           Right-to-left:
//       X   7/16                7/16   X
//   3/16  5/16  1/16        1/16  5/16  3/16
//
// Where X is current pixel. All error is diffused (100%).

// Apply Floyd-Steinberg error diffusion dithering to an entire buffer.
// Uses OkLab for palette matching. Error diffusion can be in linear RGB or OkLab space.
//
// Parameters:
//   float_fb: Input framebuffer in LINEAR RGB space (RGBA, 0.0-1.0)
//   out_fb: Output framebuffer in sRGB space (RGBA, 0-255)
//   width, height: Image dimensions (width must be <= DITHER_MAX_WIDTH)
//   palette_mode: DITHER_PALETTE_IDEAL, DITHER_PALETTE_DEVICE, or DITHER_PALETTE_BLEND
//   saturation: 0.0-1.0, blend factor (only used when palette_mode=BLEND)
//   preserve_alpha: 1 = preserve alpha from float_fb, 0 = always opaque
//   strength: 0.0-1.0, scales error diffusion (1.0 = full FS 100%, 0.0 = no diffusion)
//             Suggested default: 0.6-0.9 (lower than Atkinson since FS diffuses 100%)
//   oklab_error: 0 = diffuse error in linear RGB, 1 = diffuse error in OkLab space
//
static inline void dither_buffer_floyd_steinberg(
    const float* float_fb, uint8_t* out_fb,
    int width, int height,
    DitherPaletteMode palette_mode, float saturation, int preserve_alpha,
    float strength, int oklab_error) {

  if (width > DITHER_MAX_WIDTH) return;

  // Clamp saturation once and use consistently for caching
  float sat = clampf(saturation, 0.0f, 1.0f);

  // Get the appropriate palette based on mode - used end-to-end for matching and output
  const DitherRGB* palette = get_dither_palette(palette_mode, sat);
  init_dither_palette(palette, palette_mode, sat);

  // Floyd-Steinberg weights scaled by strength
  // FS diffuses 100% of error: 7/16 + 3/16 + 5/16 + 1/16 = 16/16 = 1
  float d7 = (7.0f / 16.0f) * strength;
  float d3 = (3.0f / 16.0f) * strength;
  float d5 = (5.0f / 16.0f) * strength;
  float d1 = (1.0f / 16.0f) * strength;

  // Clear error buffers (FS only needs 2 rows: current and next)
  for (int i = 0; i < width; i++) {
    err_curr_r[i] = err_curr_g[i] = err_curr_b[i] = 0.0f;
    err_next1_r[i] = err_next1_g[i] = err_next1_b[i] = 0.0f;
  }

  for (int y = 0; y < height; y++) {
    // Serpentine scan: alternate direction each row to reduce directional artifacts
    int left_to_right = (y % 2 == 0);
    int x_start = left_to_right ? 0 : width - 1;
    int x_end = left_to_right ? width : -1;
    int x_step = left_to_right ? 1 : -1;

    for (int x = x_start; x != x_end; x += x_step) {
      int i = (y * width + x) * 4;
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      OkLab color;
      int idx;
      float err_1, err_2, err_3;  // Error values (RGB or Lab)

      if (oklab_error) {
        // OkLab error diffusion: add accumulated error in OkLab space
        float r = clampf(float_fb[i], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
        color = linear_to_oklab(r, g, b);

        // Add accumulated OkLab error (buffers hold L, a, b)
        color.L = clampf(color.L + err_curr_r[x], 0.0f, 1.0f);
        color.a = color.a + err_curr_g[x];
        color.b = color.b + err_curr_b[x];

        idx = find_closest_palette_color_oklab(color);

        // Calculate quantization error in OkLab space
        OkLab quantized = DITHER_PALETTE_OKLAB[idx];
        err_1 = color.L - quantized.L;
        err_2 = color.a - quantized.a;
        err_3 = color.b - quantized.b;
      } else {
        // Linear RGB error diffusion (original behavior)
        float r = clampf(float_fb[i] + err_curr_r[x], 0.0f, 1.0f);
        float g = clampf(float_fb[i + 1] + err_curr_g[x], 0.0f, 1.0f);
        float b = clampf(float_fb[i + 2] + err_curr_b[x], 0.0f, 1.0f);

        color = linear_to_oklab(r, g, b);
        idx = find_closest_palette_color_oklab(color);

        // Calculate quantization error in linear RGB
        LinearRGB quantized = DITHER_PALETTE_LINEAR[idx];
        err_1 = r - quantized.r;
        err_2 = g - quantized.g;
        err_3 = b - quantized.b;
      }

      // Output the quantized color
      out_fb[i] = palette[idx].r;
      out_fb[i + 1] = palette[idx].g;
      out_fb[i + 2] = palette[idx].b;
      out_fb[i + 3] = preserve_alpha ? (uint8_t)(a * 255.0f + 0.5f) : 255;

      // Floyd-Steinberg distributes 100% of error
      int fwd = x + x_step;
      int back = x - x_step;

      // Current row: forward pixel gets 7/16
      if (fwd >= 0 && fwd < width) {
        err_curr_r[fwd] += err_1 * d7;
        err_curr_g[fwd] += err_2 * d7;
        err_curr_b[fwd] += err_3 * d7;
      }

      // Next row (y+1): back pixel gets 3/16, same x gets 5/16, forward gets 1/16
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

    // Rotate row buffers: next1 becomes current, clear next1
    for (int i = 0; i < width; i++) {
      err_curr_r[i] = err_next1_r[i];
      err_curr_g[i] = err_next1_g[i];
      err_curr_b[i] = err_next1_b[i];
      err_next1_r[i] = err_next1_g[i] = err_next1_b[i] = 0.0f;
    }
  }
}

// =================================================================================================
// Unified Dither Buffer API
// =================================================================================================
//
// Dispatches to the appropriate dithering kernel based on the kernel parameter.

static inline void dither_buffer(
    const float* float_fb, uint8_t* out_fb,
    int width, int height,
    DitherPaletteMode palette_mode, float saturation, int preserve_alpha,
    float strength, DitherKernel kernel, int oklab_error) {

  switch (kernel) {
    case DITHER_KERNEL_FLOYD_STEINBERG:
      dither_buffer_floyd_steinberg(float_fb, out_fb, width, height,
                                    palette_mode, saturation, preserve_alpha, strength, oklab_error);
      break;
    case DITHER_KERNEL_ATKINSON:
    default:
      dither_buffer_atkinson(float_fb, out_fb, width, height,
                             palette_mode, saturation, preserve_alpha, strength, oklab_error);
      break;
  }
}
