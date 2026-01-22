#pragma once

#include "math.h"

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
