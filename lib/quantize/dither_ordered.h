#pragma once

// =================================================================================================
// Ordered Dithering
// =================================================================================================
// Applies ordered dithering to quantize a linear RGB framebuffer to a limited palette.
//
// Key features:
// - OkLab color space for perceptually accurate palette matching
// - Bayer matrices (2x2, 4x4, 8x8) for regular pattern dithering
// - Configurable spread to control threshold intensity
// - Caller-provided palettes of any size
// - Caller-owned cache for embedded-friendly operation
//
// Input:  Linear RGB framebuffer (float 0.0-1.0, RGBA)
// Output: sRGB framebuffer (uint8_t 0-255, RGBA)
//
// Memory model:
// - All buffers are caller-owned (no static allocations)
// - Use DITHER_ORDERED_CACHE_STATIC() macro for easy stack allocation
// - Cache can be reused across frames if palette doesn't change

#include "quantize/dither.h"
#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Ordered Dithering Matrix Type
// -------------------------------------------------------------------------------------------------

typedef enum {
  DITHER_BAYER_2X2 = 0, // 2x2 Bayer matrix (4 threshold levels)
  DITHER_BAYER_4X4 = 1, // 4x4 Bayer matrix (16 threshold levels)
  DITHER_BAYER_8X8 = 2  // 8x8 Bayer matrix (64 threshold levels)
} DitherOrderedMatrix;

// -------------------------------------------------------------------------------------------------
// Ordered Dithering Cache
// -------------------------------------------------------------------------------------------------
// Caller-owned structure for palette state.
// All memory is allocated by caller - quantizer never allocates.
//
// Usage with static macro (recommended):
//   DITHER_ORDERED_CACHE_STATIC(cache, 64);  // 64 colors max
//   dither_ordered_apply(..., &cache);
//
// Usage with manual allocation:
//   DitherOkLab oklab[64];
//   DitherOrderedCache cache = {
//     .palette_oklab = oklab,
//     .palette_capacity = 64,
//     .last_palette = nullptr,
//     .last_palette_count = 0
//   };
//
// Note: Cache invalidation is pointer-based. If you modify palette contents
// in-place, set cache->last_palette = nullptr to force re-initialization.

typedef struct {
  // Palette cache (caller allocates, size >= palette_count)
  DitherOkLab *palette_oklab;
  int palette_capacity; // Max colors this cache can hold

  // Cache invalidation tracking (managed internally)
  const DitherRGB *last_palette;
  int last_palette_count;
} DitherOrderedCache;

// -------------------------------------------------------------------------------------------------
// Static Cache Allocation Macro
// -------------------------------------------------------------------------------------------------
// Allocates a DitherOrderedCache with all buffers on the stack (or as static).
//
// Example:
//   DITHER_ORDERED_CACHE_STATIC(my_cache, 6);  // 6 colors
//   dither_ordered_apply(in, out, 400, 400, &config, &my_cache);

#define DITHER_ORDERED_CACHE_STATIC(name, max_colors)                                              \
  DitherOkLab name##_oklab[max_colors];                                                            \
  DitherOrderedCache name = {.palette_oklab = name##_oklab,                                        \
                             .palette_capacity = (max_colors),                                     \
                             .last_palette = nullptr,                                              \
                             .last_palette_count = 0}

// -------------------------------------------------------------------------------------------------
// Ordered Dithering Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  // Palette (required)
  const DitherRGB *palette; // Pointer to palette colors
  int palette_count;        // Number of colors in palette

  // Algorithm settings
  DitherOrderedMatrix matrix; // DITHER_BAYER_2X2, _4X4, or _8X8
  float spread;               // Threshold spread (0.0-1.0, default 0.5)
  float chroma_weight;        // Weight for hue/chroma vs lightness (0.5-4.0, default 1.0)
} DitherOrderedConfig;

// -------------------------------------------------------------------------------------------------
// Ordered Dithering Functions
// -------------------------------------------------------------------------------------------------

// Initialize the cache for a given palette.
// Called automatically by dither_ordered_apply if palette changed, but can be called
// explicitly to pre-warm the cache.
//
// Returns 0 on success, -1 if cache capacity is insufficient.
int dither_ordered_init_cache(DitherOrderedCache *cache, const DitherRGB *palette,
                              int palette_count);

// Apply ordered dithering to a framebuffer.
// Input:  float_fb - linear RGB framebuffer (RGBA, 0.0-1.0)
// Output: out_fb - sRGB framebuffer (RGBA, 0-255)
// Config: dither settings including palette
// Cache:  caller-owned cache (required, use DITHER_ORDERED_CACHE_STATIC for easy setup)
//
// Returns 0 on success, -1 on error (null pointers, palette exceeds cache capacity).
int dither_ordered_apply(const float *float_fb, uint8_t *out_fb, int width, int height,
                         const DitherOrderedConfig *config, DitherOrderedCache *cache);
