#include <stdint.h>

// =================================================================================================
// Math Constants
// =================================================================================================

#define PI 3.14159265358979323846f
#define TAU (2.0f * PI)
#define EPS_NORM 1e-9f
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
// Power Approximations (for wavelength_to_rgb)
// =================================================================================================

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

// =================================================================================================
// Prism Geometry (Simplified - no optical properties)
// =================================================================================================

typedef struct {
  float vertices[6];  // 3 vertices x 2 coords
} Prism;

// Create an isosceles triangle prism with apex at top, centered at (cx, cy).
// apex_angle_deg: angle at the apex (top vertex)
// size: width of the base
static void create_prism(
  float cx, float cy, float size,
  float apex_angle_deg,
  Prism* out
) {
  float half_apex_rad = (apex_angle_deg / 2.0f) * PI / 180.0f;
  float cos_half = cosf_approx(half_apex_rad);
  if (fabsf_impl(cos_half) < EPS_NORM) cos_half = EPS_NORM;
  float tan_half = sinf_approx(half_apex_rad) / cos_half;
  float h = (size / 2.0f) / tan_half;

  float apex_offset = (2.0f * h) / 3.0f;
  float base_offset = h / 3.0f;

  // v0 = apex (top), v1 = bottom-right, v2 = bottom-left
  out->vertices[0] = cx;
  out->vertices[1] = cy - apex_offset;
  out->vertices[2] = cx + size / 2.0f;
  out->vertices[3] = cy + base_offset;
  out->vertices[4] = cx - size / 2.0f;
  out->vertices[5] = cy + base_offset;
}

// =================================================================================================
// Ray-Segment Intersection
// =================================================================================================

typedef struct {
  int hit;
  float t;      // Parameter along ray
  float px, py; // Hit point
} RayHit;

// Intersect ray (ox, oy) + t*(dx, dy) with line segment (ax, ay)-(bx, by).
// Returns hit info if intersection found with t > eps.
static RayHit ray_segment_intersect(
  float ox, float oy, float dx, float dy,
  float ax, float ay, float bx, float by,
  float eps
) {
  RayHit result = {0, 0.0f, 0.0f, 0.0f};

  float ex = bx - ax;
  float ey = by - ay;

  // Ray perpendicular
  float perp_x = -dy;
  float perp_y = dx;

  float denom = ex * perp_x + ey * perp_y;
  if (fabsf_impl(denom) < EPS_NORM) return result;  // Parallel

  float vx = ox - ax;
  float vy = oy - ay;

  float t = (ex * vy - ey * vx) / denom;
  if (t < eps) return result;  // Behind ray origin

  float u = (vx * perp_x + vy * perp_y) / denom;
  if (u < 0.0f || u > 1.0f) return result;  // Outside segment

  result.hit = 1;
  result.t = t;
  result.px = ox + dx * t;
  result.py = oy + dy * t;
  return result;
}

// Find where a ray from (ox, oy) in direction (dx, dy) first enters the prism.
// Returns hit info with the entry point.
static RayHit find_prism_entry(
  float ox, float oy, float dx, float dy,
  const Prism* prism
) {
  RayHit best = {0, T_MAX, 0.0f, 0.0f};
  float eps = 1e-6f;

  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float ax = prism->vertices[i * 2];
    float ay = prism->vertices[i * 2 + 1];
    float bx = prism->vertices[j * 2];
    float by = prism->vertices[j * 2 + 1];

    RayHit hit = ray_segment_intersect(ox, oy, dx, dy, ax, ay, bx, by, eps);
    if (hit.hit && hit.t < best.t) {
      best = hit;
    }
  }

  return best;
}

// Find where a ray from center in direction (angle) exits the prism.
// This is used for the exit rays that appear to originate from center.
static RayHit find_prism_exit_from_center(
  float cx, float cy, float angle,
  const Prism* prism
) {
  float dx = cosf_approx(angle);
  float dy = sinf_approx(angle);

  // We want the SECOND intersection (exit point), not entry.
  // Start from center, find all intersections, take the farthest.
  RayHit best = {0, 0.0f, 0.0f, 0.0f};
  float eps = 1e-6f;

  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    float ax = prism->vertices[i * 2];
    float ay = prism->vertices[i * 2 + 1];
    float bx = prism->vertices[j * 2];
    float by = prism->vertices[j * 2 + 1];

    RayHit hit = ray_segment_intersect(cx, cy, dx, dy, ax, ay, bx, by, eps);
    if (hit.hit && hit.t > best.t) {
      best = hit;
    }
  }

  return best;
}

// =================================================================================================
// Ray-Circle Intersection
// =================================================================================================

static int ray_circle_intersection(
  float ox, float oy, float dx, float dy,
  float cx, float cy, float radius,
  float* out_x, float* out_y
) {
  float len = sqrtf_impl(dx * dx + dy * dy);
  if (len <= EPS_NORM) return 0;
  float inv_len = 1.0f / len;
  dx *= inv_len;
  dy *= inv_len;

  float fx = ox - cx;
  float fy = oy - cy;

  float b = 2.0f * (fx * dx + fy * dy);
  float c = fx * fx + fy * fy - radius * radius;
  float discriminant = b * b - 4.0f * c;

  if (discriminant < 0.0f) return 0;

  float sqrt_disc = sqrtf_impl(discriminant);
  float t1 = (-b + sqrt_disc) * 0.5f;
  float t2 = (-b - sqrt_disc) * 0.5f;

  float eps = 1e-6f;
  float t;
  if (t2 > eps) {
    t = t2;
  } else if (t1 > eps) {
    t = t1;
  } else {
    return 0;
  }

  *out_x = ox + dx * t;
  *out_y = oy + dy * t;
  return 1;
}
