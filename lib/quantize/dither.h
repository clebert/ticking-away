#pragma once

// =================================================================================================
// Dither Quantizer
// =================================================================================================
// Applies error diffusion dithering to quantize a linear RGB framebuffer to a limited palette.
//
// Key features:
// - OkLab color space for perceptually accurate palette matching
// - Atkinson (75% error) and Floyd-Steinberg (100% error) algorithms
// - Serpentine scanning to reduce directional artifacts
// - Caller-provided palettes of any size (6, 64, etc.)
// - Caller-owned cache/buffers for embedded-friendly operation
// - Optional B/W-only dithering for grayscale regions
//
// Input:  Linear RGB framebuffer (float 0.0-1.0, RGBA)
// Output: sRGB framebuffer (uint8_t 0-255, RGBA)
//
// Memory model:
// - All buffers are caller-owned (no static allocations)
// - Use DITHER_CACHE_STATIC() macro for easy stack allocation
// - Cache can be reused across frames if palette doesn't change

#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Dither Algorithm Type
// -------------------------------------------------------------------------------------------------

typedef enum {
  DITHER_ATKINSON = 0,       // Atkinson: diffuses 75% of error, higher contrast
  DITHER_FLOYD_STEINBERG = 1 // Floyd-Steinberg: diffuses 100%, smoother gradients
} DitherAlgorithm;

// -------------------------------------------------------------------------------------------------
// Palette RGB Type
// -------------------------------------------------------------------------------------------------

typedef struct {
  uint8_t r, g, b;
} DitherRGB;

// -------------------------------------------------------------------------------------------------
// Standard Palettes (convenience constants)
// -------------------------------------------------------------------------------------------------
// These are provided for convenience. Callers can also provide custom palettes.

// Pure RGB palette (ideal target colors) - 6 colors
extern const DitherRGB DITHER_PALETTE_IDEAL[];
enum { DITHER_PALETTE_IDEAL_COUNT = 6 };

// Inky Impression 13.3" device palette (Spectra 6) - 6 colors
extern const DitherRGB DITHER_PALETTE_DEVICE[];
enum { DITHER_PALETTE_DEVICE_COUNT = 6 };

// Measured Spectra 6 palette (from epdoptimize) - 6 colors
extern const DitherRGB DITHER_PALETTE_SPECTRA6[];
enum { DITHER_PALETTE_SPECTRA6_COUNT = 6 };

// -------------------------------------------------------------------------------------------------
// OkLab Color Type
// -------------------------------------------------------------------------------------------------
// OkLab is a perceptually uniform color space, ideal for color matching.

typedef struct {
  float L, a, b;
} DitherOkLab;

// -------------------------------------------------------------------------------------------------
// Linear RGB Type
// -------------------------------------------------------------------------------------------------

typedef struct {
  float r, g, b;
} DitherLinearRGB;

// -------------------------------------------------------------------------------------------------
// Dither Cache
// -------------------------------------------------------------------------------------------------
// Caller-owned structure for palette state and error diffusion buffers.
// All memory is allocated by caller - quantizer never allocates.
//
// Usage with static macro (recommended):
//   DITHER_CACHE_STATIC(cache, 64, 1920);  // 64 colors, 1920 max width
//   quantize_dither_apply(..., &cache);
//
// Usage with manual allocation:
//   DitherOkLab oklab[64];
//   DitherLinearRGB linear[64];
//   float err[1920 * 9];  // 3 rows * 3 channels * width
//   DitherCache cache = {
//     .palette_oklab = oklab,
//     .palette_linear = linear,
//     .palette_capacity = 64,
//     .err_buffer = err,
//     .err_row_width = 1920
//   };
//
// Note: Cache invalidation is pointer-based. If you modify palette contents
// in-place, set cache->last_palette = NULL to force re-initialization.

typedef struct {
  // Palette cache (caller allocates, size >= palette_count)
  DitherOkLab *palette_oklab;
  DitherLinearRGB *palette_linear;
  int palette_capacity; // Max colors this cache can hold

  // Error diffusion buffers (caller allocates, size >= width * 9)
  // Layout: 3 rows × 3 channels (RGB), interleaved by row
  // row0_r[0..w-1], row0_g[0..w-1], row0_b[0..w-1], row1_r[0..w-1], ...
  float *err_buffer;
  int err_row_width; // Max width this cache can handle

  // Cache invalidation tracking (managed internally)
  const DitherRGB *last_palette;
  int last_palette_count;
} DitherCache;

// -------------------------------------------------------------------------------------------------
// Static Cache Allocation Macro
// -------------------------------------------------------------------------------------------------
// Allocates a DitherCache with all buffers on the stack (or as static).
//
// Example:
//   DITHER_CACHE_STATIC(my_cache, 6, 400);  // 6 colors, 400px wide
//   quantize_dither_apply(in, out, 400, 400, &config, &my_cache);

#define DITHER_CACHE_STATIC(name, max_colors, max_width)                                           \
  DitherOkLab name##_oklab[max_colors];                                                            \
  DitherLinearRGB name##_linear[max_colors];                                                       \
  float name##_err[(max_width) * 9];                                                               \
  DitherCache name = {.palette_oklab = name##_oklab,                                               \
                      .palette_linear = name##_linear,                                             \
                      .palette_capacity = (max_colors),                                            \
                      .err_buffer = name##_err,                                                    \
                      .err_row_width = (max_width),                                                \
                      .last_palette = 0,                                                           \
                      .last_palette_count = 0}

// -------------------------------------------------------------------------------------------------
// Dither Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  // Palette (required)
  const DitherRGB *palette; // Pointer to palette colors
  int palette_count;        // Number of colors in palette

  // B/W threshold settings (optional)
  int bw_black_idx; // Palette index for black (used when bw_threshold > 0)
  int bw_white_idx; // Palette index for white (used when bw_threshold > 0)

  // Algorithm settings
  DitherAlgorithm algorithm; // DITHER_ATKINSON or DITHER_FLOYD_STEINBERG
  float strength;            // Error diffusion strength (0.0-1.0, typically 1.0)
  int oklab_error;           // Use OkLab error diffusion (0 or 1)
  int preserve_alpha;        // Preserve alpha from input (0 or 1)
  float bw_threshold;        // OkLab chroma threshold for B/W-only (0.0 = disabled)
  float chroma_weight;       // Weight for hue/chroma vs lightness (0.5-4.0, default 1.0)
} DitherConfig;

// -------------------------------------------------------------------------------------------------
// Quantizer Functions
// -------------------------------------------------------------------------------------------------

// Initialize the cache for a given palette.
// Called automatically by quantize_dither_apply if palette changed, but can be called
// explicitly to pre-warm the cache.
//
// Returns 0 on success, -1 if cache capacity is insufficient.
int quantize_dither_init_cache(DitherCache *cache, const DitherRGB *palette, int palette_count);

// Apply error diffusion dithering to a framebuffer.
// Input:  float_fb - linear RGB framebuffer (RGBA, 0.0-1.0)
// Output: out_fb - sRGB framebuffer (RGBA, 0-255)
// Config: dither settings including palette
// Cache:  caller-owned cache (required, use DITHER_CACHE_STATIC for easy setup)
//
// Returns 0 on success, -1 on error (null pointers, width exceeds cache capacity).
int quantize_dither_apply(const float *float_fb, uint8_t *out_fb, int width, int height,
                          const DitherConfig *config, DitherCache *cache);

// -------------------------------------------------------------------------------------------------
// Utility Functions (exposed for testing)
// -------------------------------------------------------------------------------------------------

// Convert linear RGB to OkLab
DitherOkLab dither_linear_to_oklab(float r, float g, float b);

// Convert sRGB (0-255) to linear (0.0-1.0)
float dither_srgb_to_linear(uint8_t srgb);

// Compute OkLab chroma (saturation metric)
float dither_oklab_chroma(DitherOkLab color);

// OkLab weighted distance squared
float dither_oklab_distance_sq(DitherOkLab a, DitherOkLab b, float chroma_weight);

// Find closest palette color index using OkLab distance
int dither_find_closest_color(DitherOkLab color, const DitherOkLab *palette, int palette_count,
                              float chroma_weight);

// Find closest color from two specified indices (for B/W threshold)
int dither_find_closest_bw(DitherOkLab color, const DitherOkLab *palette, int black_idx,
                           int white_idx, float chroma_weight);
