#include "draw/pixel.h"
#include "fastmath.h"

// =================================================================================================
// Falloff Computation
// =================================================================================================

// Exponential falloff constant: -3 / ln(2) for exp(-3*t) = exp2(EXP_NEG3_FACTOR * t)
#define EXP_NEG3_FACTOR (-4.328085f)

float compute_falloff(FalloffType type, float t) {
  float one_minus_t = 1.0f - t;
  switch (type) {
  case FALLOFF_LINEAR:
    return one_minus_t;
  case FALLOFF_QUADRATIC:
    return one_minus_t * one_minus_t;
  case FALLOFF_CUBIC:
    return one_minus_t * one_minus_t * one_minus_t;
  case FALLOFF_EXPONENTIAL:
    return fast_exp2f(EXP_NEG3_FACTOR * t) * one_minus_t;
  default:
    return one_minus_t * one_minus_t;
  }
}

// =================================================================================================
// Additive Blending
// =================================================================================================

void pixel_add(float *fb, int width, int height, int x, int y, float r, float g, float b, float a) {
  if (x < 0 || x >= width || y < 0 || y >= height)
    return;

  int idx = (y * width + x) * 4;
  fb[idx] += r * a;
  fb[idx + 1] += g * a;
  fb[idx + 2] += b * a;
  // Alpha channel not modified (assumed pre-initialized to 1.0)
}

// =================================================================================================
// Alpha Blending
// =================================================================================================

void pixel_blend(float *fb, int width, int height, int x, int y, float r, float g, float b,
                 float a) {
  if (x < 0 || x >= width || y < 0 || y >= height)
    return;

  int idx = (y * width + x) * 4;
  float inv_a = 1.0f - a;
  fb[idx] = r * a + fb[idx] * inv_a;
  fb[idx + 1] = g * a + fb[idx + 1] * inv_a;
  fb[idx + 2] = b * a + fb[idx + 2] * inv_a;
  fb[idx + 3] = 1.0f;
}
