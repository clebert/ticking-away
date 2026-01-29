#pragma once

// =================================================================================================
// Error Diffusion Dithering
// =================================================================================================
// Applies error diffusion dithering to quantize a linear RGB framebuffer to a limited palette.
//
// Key features:
// - OkLab color space for perceptually accurate palette matching
// - Atkinson (75% error) and Floyd-Steinberg (100% error) algorithms
// - Serpentine scanning to reduce directional artifacts
// - Caller-provided palettes of any size (6, 64, etc.)
// - Caller-owned cache/buffers for embedded-friendly operation
//
// Input:  Linear RGB framebuffer (float 0.0-1.0, RGBA)
// Output: sRGB framebuffer (uint8_t 0-255, RGBA)
//
// Memory model:
// - All buffers are caller-owned (no static allocations)
// - Use DITHER_ERROR_CACHE_STATIC() macro for easy stack allocation
// - Cache can be reused across frames if palette doesn't change

#include "quantize/dither.h"
#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Error Diffusion Algorithm
// -------------------------------------------------------------------------------------------------

typedef enum {
  DITHER_ATKINSON = 0,       // Atkinson: diffuses 75% of error, higher contrast
  DITHER_FLOYD_STEINBERG = 1 // Floyd-Steinberg: diffuses 100%, smoother gradients
} DitherErrorAlgorithm;

// -------------------------------------------------------------------------------------------------
// Error Diffusion Cache
// -------------------------------------------------------------------------------------------------
// Caller-owned structure for palette state and error diffusion buffers.
// All memory is allocated by caller - quantizer never allocates.
//
// Usage with static macro (recommended):
//   DITHER_ERROR_CACHE_STATIC(cache, 64, 1920);  // 64 colors, 1920 max width
//   dither_error_apply(..., &cache);
//
// Usage with manual allocation:
//   DitherOkLab oklab[64];
//   DitherLinearRGB linear[64];
//   float err[1920 * 9];  // 3 rows * 3 channels * width
//   DitherErrorCache cache = {
//     .palette_oklab = oklab,
//     .palette_linear = linear,
//     .palette_capacity = 64,
//     .err_buffer = err,
//     .err_row_width = 1920
//   };
//
// Note: Cache invalidation is pointer-based. If you modify palette contents
// in-place, set cache->last_palette = nullptr to force re-initialization.

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
} DitherErrorCache;

// -------------------------------------------------------------------------------------------------
// Static Cache Allocation Macro
// -------------------------------------------------------------------------------------------------
// Allocates a DitherErrorCache with all buffers on the stack (or as static).
//
// Example:
//   DITHER_ERROR_CACHE_STATIC(my_cache, 6, 400);  // 6 colors, 400px wide
//   dither_error_apply(in, out, 400, 400, &config, &my_cache);

#define DITHER_ERROR_CACHE_STATIC(name, max_colors, max_width)                                     \
  DitherOkLab name##_oklab[max_colors];                                                            \
  DitherLinearRGB name##_linear[max_colors];                                                       \
  float name##_err[(max_width) * 9];                                                               \
  DitherErrorCache name = {.palette_oklab = name##_oklab,                                          \
                           .palette_linear = name##_linear,                                        \
                           .palette_capacity = (max_colors),                                       \
                           .err_buffer = name##_err,                                               \
                           .err_row_width = (max_width),                                           \
                           .last_palette = nullptr,                                                \
                           .last_palette_count = 0}

// -------------------------------------------------------------------------------------------------
// Error Diffusion Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  // Palette (required)
  const DitherRGB *palette; // Pointer to palette colors
  int palette_count;        // Number of colors in palette

  // Algorithm settings
  DitherErrorAlgorithm algorithm; // DITHER_ATKINSON or DITHER_FLOYD_STEINBERG
  float strength;                 // Error diffusion strength (0.0-1.0, typically 1.0)
  int oklab_error;                // Use OkLab error diffusion (0 or 1)
  float chroma_weight;            // Weight for hue/chroma vs lightness (0.5-4.0, default 1.0)
} DitherErrorConfig;

// -------------------------------------------------------------------------------------------------
// Error Diffusion Functions
// -------------------------------------------------------------------------------------------------

// Initialize the cache for a given palette.
// Called automatically by dither_error_apply if palette changed, but can be called
// explicitly to pre-warm the cache.
//
// Returns 0 on success, -1 if cache capacity is insufficient.
int dither_error_init_cache(DitherErrorCache *cache, const DitherRGB *palette, int palette_count);

// Apply error diffusion dithering to a framebuffer.
// Input:  float_fb - linear RGB framebuffer (RGBA, 0.0-1.0)
// Output: out_fb - sRGB framebuffer (RGBA, 0-255)
// Config: dither settings including palette
// Cache:  caller-owned cache (required, use DITHER_ERROR_CACHE_STATIC for easy setup)
//
// Returns 0 on success, -1 on error (null pointers, width exceeds cache capacity).
int dither_error_apply(const float *float_fb, uint8_t *out_fb, int width, int height,
                       const DitherErrorConfig *config, DitherErrorCache *cache);
