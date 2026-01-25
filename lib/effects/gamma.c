#include "effects/gamma.h"
#include "effects/effect.h"
#include "fastmath.h"

// =================================================================================================
// Color Space Conversion Implementation
// =================================================================================================

float gamma_srgb_to_linear(uint8_t srgb) {
  float s = (float)srgb / 255.0f;
  if (s <= 0.04045f) {
    return s / 12.92f;
  }
  // Clamp output to [0,1] because fast_powf approximation can slightly exceed 1.0
  // at boundary values (e.g., srgb=255 would give ~1.098 without clamping)
  float result = fast_powf((s + 0.055f) / 1.055f, 2.4f);
  return clampf(result, 0.0f, 1.0f);
}

float gamma_linear_to_srgb(float linear) {
  if (linear <= 0.0031308f) {
    return linear * 12.92f;
  }
  // Use accurate_pow_5_12 (x^(5/12) = x^(1/2.4)) to eliminate banding in dark regions
  return 1.055f * accurate_pow_5_12(linear) - 0.055f;
}

// =================================================================================================
// Effect Implementation
// =================================================================================================

void effect_gamma_apply(float *fb, int width, int height, const void *config, const void *cache) {
  (void)config; // Currently unused
  (void)cache;  // Currently unused

  int total_pixels = width * height;

  for (int i = 0; i < total_pixels; i++) {
    int idx = i * 4;

    // Clamp values (additive blending can exceed 1.0)
    float r = clampf(fb[idx], 0.0f, 1.0f);
    float g = clampf(fb[idx + 1], 0.0f, 1.0f);
    float b = clampf(fb[idx + 2], 0.0f, 1.0f);
    // Alpha unchanged

    // Apply proper sRGB gamma correction (linear -> sRGB)
    fb[idx] = gamma_linear_to_srgb(r);
    fb[idx + 1] = gamma_linear_to_srgb(g);
    fb[idx + 2] = gamma_linear_to_srgb(b);
  }
}

// Effect descriptor
const Effect EFFECT_GAMMA = {.name = "gamma", .apply = effect_gamma_apply};
