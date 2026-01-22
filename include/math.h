#pragma once

#include <stdint.h>

// =================================================================================================
// Math Constants
// =================================================================================================

#define PI 3.14159265358979323846f
#define TAU (2.0f * PI)
#define EPS_NORM 1e-9f
#define EPS_PARALLEL 1e-7f  // Scale factor for parallel detection (relative to vector magnitudes)
#define EPS_REL 1e-5f       // Scale factor for tolerances (t in world units, u dimensionless)
#define T_MAX 1e30f

// =================================================================================================
// Basic Math Functions
// =================================================================================================

static inline float fabsf_impl(float x) {
  return x < 0.0f ? -x : x;
}

static inline float maxf_impl(float a, float b) {
  return a > b ? a : b;
}

static inline float minf_impl(float a, float b) {
  return a < b ? a : b;
}

static inline float sqrtf_impl(float x) {
  return __builtin_sqrtf(x);
}

static inline float cbrtf_impl(float x) {
  // Fast cube root using Newton-Raphson with bit manipulation initial guess
  if (x == 0.0f) return 0.0f;
  int neg = x < 0.0f;
  if (neg) x = -x;
  union { float f; uint32_t u; } v = { x };
  v.u = (v.u / 3) + 709921077;  // Initial guess via bit hack
  float y = v.f;
  // Three Newton iterations for high accuracy
  y = (2.0f * y + x / (y * y)) / 3.0f;
  y = (2.0f * y + x / (y * y)) / 3.0f;
  y = (2.0f * y + x / (y * y)) / 3.0f;
  return neg ? -y : y;
}

static inline float clampf(float x, float lo, float hi) {
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

// Reduces angle to [-PI, PI] range.
static inline float reduce_angle(float x) {
  float n = x * (1.0f / TAU);
  int ni = (int)n;
  if (n < (float)ni) ni--;
  x = x - (float)ni * TAU;
  if (x > PI) x -= TAU;
  if (x < -PI) x += TAU;
  return x;
}

static inline float ang_dist(float a, float b) {
  return fabsf_impl(reduce_angle(a - b));
}

// =================================================================================================
// Trigonometric Approximations
// =================================================================================================

static inline float sinf_approx(float x) {
  x = reduce_angle(x);
  float sign = 1.0f;
  if (x < 0.0f) {
    x = -x;
    sign = -1.0f;
  }
  float pmx = PI - x;
  float num = 16.0f * x * pmx;
  float den = 5.0f * PI * PI - 4.0f * x * pmx;
  return sign * num / den;
}

static inline float cosf_approx(float x) {
  return sinf_approx(x + PI / 2.0f);
}

static inline float atan2_approx(float y, float x) {
  if (x == 0.0f) {
    if (y > 0.0f) return PI * 0.5f;
    if (y < 0.0f) return -PI * 0.5f;
    return 0.0f;
  }
  if (y == 0.0f) {
    return (x < 0.0f) ? PI : 0.0f;
  }

  float abs_y = fabsf_impl(y);
  float angle;
  if (x >= 0.0f) {
    float r = (x - abs_y) / (x + abs_y);
    angle = 0.1963f * r * r * r - 0.9817f * r + PI / 4.0f;
  } else {
    float r = (x + abs_y) / (abs_y - x);
    angle = 0.1963f * r * r * r - 0.9817f * r + 3.0f * PI / 4.0f;
  }
  return y < 0.0f ? -angle : angle;
}

// =================================================================================================
// Power Approximations
// =================================================================================================
//
// NOTE: These functions assume IEEE-754 float layout and use union type-punning.
// Callers should ensure x > 0 for fast_log2f (no denormals/zero/negative).

static inline float fast_log2f(float x) {
  union { float f; uint32_t u; } v = { x };
  float log2 = (float)((int32_t)(v.u >> 23) - 127);
  v.u = (v.u & 0x007FFFFF) | 0x3F800000;
  float m = v.f;
  log2 += -1.7417939f + m * (2.8212026f + m * (-1.4699568f + m * 0.44717955f));
  return log2;
}

static inline float fast_exp2f(float x) {
  if (x < -126.0f) return 0.0f;
  if (x >= 128.0f) return 1e38f;
  int32_t i = (int32_t)x;
  if (x < (float)i) i--;
  float f = x - (float)i;
  float p = 1.0f + f * (0.6931472f + f * (0.2402265f + f * (0.0555041f + f * 0.0096139f)));
  union { float f; int32_t i; } u;
  u.i = (i + 127) << 23;
  return u.f * p;
}

static inline float fast_powf(float x, float y) {
  if (x <= 0.0f) return 0.0f;
  return fast_exp2f(y * fast_log2f(x));
}

// Accurate x^(5/12) for sRGB gamma conversion (linear -> sRGB).
// Uses cbrt and sqrt operations which are more accurate than log/exp approximations.
// x^(5/12) = cbrt(x)^(5/4) = cbrt(x) * fourth_root(cbrt(x))
//          = cbrt(x) * sqrt(sqrt(cbrt(x)))
static inline float accurate_pow_5_12(float x) {
  if (x <= 0.0f) return 0.0f;
  if (x >= 1.0f) return 1.0f;

  float cbrt_x = cbrtf_impl(x);
  float fourth_root_cbrt = sqrtf_impl(sqrtf_impl(cbrt_x));
  return cbrt_x * fourth_root_cbrt;
}

// =================================================================================================
// Vector Operations
// =================================================================================================

static inline int vec2_normalize(float* x, float* y) {
  float len = sqrtf_impl((*x) * (*x) + (*y) * (*y));
  if (len > EPS_NORM) {
    float inv = 1.0f / len;
    *x *= inv;
    *y *= inv;
    return 1;
  }
  *x = 0.0f;
  *y = 0.0f;
  return 0;
}

static inline float vec2_dot(float ax, float ay, float bx, float by) {
  return ax * bx + ay * by;
}

static inline float vec2_length(float x, float y) {
  return sqrtf_impl(x * x + y * y);
}
