#pragma once

// =================================================================================================
// Vignette Effect
// =================================================================================================
// Applies a vignette effect to the UI background area outside the watch circle.
//
// This effect fills pixels outside the watch circle with a grey background and
// applies darkening that increases toward the corners of the framebuffer.
// Dithering noise is added to break up banding in the dark gradient.
//
// This effect expects the framebuffer to be in sRGB space (i.e., gamma correction already applied).
// Pixels inside the watch circle are left unchanged.

#include "effect.h"
#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Vignette Configuration
// -------------------------------------------------------------------------------------------------
// See config.h for VignetteConfig definition:
//   - enabled: 0 or 1
//   - strength: 0.0-1.0 max darkening at corners (default 0.4 = 40%)
//   - background: 0.0-1.0 grey level in sRGB (default ~0.137 = 35/255)

// -------------------------------------------------------------------------------------------------
// Geometry Context
// -------------------------------------------------------------------------------------------------
// Vignette requires the watch circle bounds to know which pixels are "background".
// Pass this through the cache parameter.

typedef struct {
  float cx, cy; // Circle center coordinates
  float radius; // Circle radius
} VignetteGeometry;

// -------------------------------------------------------------------------------------------------
// Hash Function
// -------------------------------------------------------------------------------------------------
// Deterministic hash for pixel coordinates (same as grain).
// Returns a uniformly distributed 32-bit value for dither noise.

static inline uint32_t vignette_hash_pixel(int x, int y) {
  uint32_t h = (uint32_t)(x * 374761393 + y * 668265263);
  h = (h ^ (h >> 13)) * 1274126177;
  return h ^ (h >> 16);
}

// -------------------------------------------------------------------------------------------------
// Effect Function
// -------------------------------------------------------------------------------------------------

// Apply vignette effect to framebuffer background.
// Expects fb to be in sRGB space (float 0.0-1.0).
// Config: pointer to VignetteConfig (from config.h). If nullptr, no effect is applied.
// Cache: pointer to VignetteGeometry (required, defines watch circle bounds).
void effect_vignette_apply(float *fb, int width, int height, const void *config, const void *cache);

// Effect descriptor for pipeline registration
extern const Effect EFFECT_VIGNETTE;
