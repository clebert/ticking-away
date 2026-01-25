#pragma once

// =================================================================================================
// Grain Effect
// =================================================================================================
// Applies film grain effect to a framebuffer in sRGB space.
//
// Grain is applied AFTER gamma correction for authentic film grain look (perceptually uniform).
// The noise is deterministic (based on pixel coordinates) so results are reproducible.
// Grain intensity scales with pixel brightness to avoid noise on black areas.
//
// This effect expects the framebuffer to be in sRGB space (i.e., gamma correction already applied).

#include "effect.h"
#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Grain Configuration
// -------------------------------------------------------------------------------------------------
// See config.h for GrainConfig definition:
//   - intensity: 0.0-1.0 grain strength
//   - scale: DPR to scale grain size (1.0 = no scaling)
//   - threshold: 0.01-1.0 brightness threshold for full grain intensity
//   - prism_only: apply grain only inside prism (requires GrainGeometry in cache)

// -------------------------------------------------------------------------------------------------
// Geometry Context (for prism_only mode)
// -------------------------------------------------------------------------------------------------
// When GrainConfig.prism_only is set, pass a GrainGeometry struct through the cache parameter.
// This allows grain to be applied only within specific regions.

typedef struct {
  // Circle bounds (grain region)
  float cx, cy; // Center coordinates
  float radius; // Circle radius

  // Prism vertices (for prism_only mode, can be NULL if not using prism mask)
  // Stored as [x0, y0, x1, y1, x2, y2] or NULL
  const float *prism_vertices;
} GrainGeometry;

// -------------------------------------------------------------------------------------------------
// Hash Function
// -------------------------------------------------------------------------------------------------
// Deterministic hash for pixel coordinates (also used by dithering).
// Returns a uniformly distributed 32-bit value.

static inline uint32_t grain_hash_pixel(int x, int y) {
  uint32_t h = (uint32_t)(x * 374761393 + y * 668265263);
  h = (h ^ (h >> 13)) * 1274126177;
  return h ^ (h >> 16);
}

// -------------------------------------------------------------------------------------------------
// Effect Function
// -------------------------------------------------------------------------------------------------

// Apply film grain to framebuffer.
// Expects fb to be in sRGB space (float 0.0-1.0).
// Config: pointer to GrainConfig (from config.h). If NULL, no grain is applied.
// Cache: pointer to GrainGeometry (optional, required for prism_only mode).
void effect_grain_apply(float *fb, int width, int height, const void *config, const void *cache);

// Effect descriptor for pipeline registration
extern const Effect EFFECT_GRAIN;
