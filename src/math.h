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
  // Clamp to avoid degenerate triangles (tan_half → 0 or cos_half → 0)
  apex_angle_deg = clampf(apex_angle_deg, 1.0f, 179.0f);
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
  float t;        // Parameter along ray
  float u;        // Parameter along edge (0=start vertex, 1=end vertex), -1 if not set
  int edge_idx;   // Which edge was hit (0, 1, 2 for prism), -1 if not set
  float px, py;   // Hit point
} RayHit;

// Intersect ray (ox, oy) + t*(dx, dy) with line segment (ax, ay)-(bx, by).
// Returns hit info if intersection found with t > eps.
static RayHit ray_segment_intersect(
  float ox, float oy, float dx, float dy,
  float ax, float ay, float bx, float by,
  float eps
) {
  RayHit result = {0, 0.0f, -1.0f, -1, 0.0f, 0.0f};

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
  // Use tolerance to avoid missing vertex hits due to floating-point noise
  if (u < -1e-6f || u > 1.0f + 1e-6f) return result;  // Outside segment
  u = clampf(u, 0.0f, 1.0f);

  result.hit = 1;
  result.t = t;
  result.u = u;  // Store parametric position along edge
  result.px = ox + dx * t;
  result.py = oy + dy * t;
  return result;
}

// Find where a ray from (ox, oy) in direction (dx, dy) first enters the prism.
// Returns hit info with the entry point, edge index, and parametric position along edge.
static RayHit find_prism_entry(
  float ox, float oy, float dx, float dy,
  const Prism* prism
) {
  RayHit best = {0, T_MAX, -1.0f, -1, 0.0f, 0.0f};
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
      best.edge_idx = i;  // Store which edge was hit
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

  // From center (inside triangle), there's exactly one forward boundary hit.
  // Take the farthest t for stability in degenerate cases (vertex ties / tiny noise).
  RayHit best = {0, 0.0f, -1.0f, -1, 0.0f, 0.0f};
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
      best.edge_idx = i;
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

// =================================================================================================
// Light Ray Bounce Detection
// =================================================================================================
//
// Problem: When the light ray's entry and exit points are on the same prism face, the internal
// path runs along (or parallel to) that edge. This makes the prism interior appear dark because
// no light visibly traverses it.
//
// Solution: Detect these "edge-hugging" cases and route the light through the opposite vertex,
// creating a two-segment path (entry → bounce vertex → exit) that illuminates the interior.
//
// Prism geometry (equilateral triangle, apex up):
//
//                 v0 (12 o'clock, -π/2)
//                 /\
//                /  \
//     Face 2    /    \    Face 0
//     (left)   /      \   (right)
//             /________\
//           v2          v1
//     (8 o'clock)    (4 o'clock)
//       (5π/6)         (π/6)
//
//              Face 1 (bottom)
//
// Face definitions:
//   Face 0 (right):  v0 → v1, covers hour angles from -π/2 to π/6
//   Face 1 (bottom): v1 → v2, covers hour angles from π/6 to 5π/6
//   Face 2 (left):   v2 → v0, covers hour angles from 5π/6 to -π/2 (wrapping)
//
// Bounce rules:
//   - Entry on face F, exit on face F → bounce through vertex (F+2)%3 (opposite vertex)
//   - Entry at vertex V, exit NOT on face (V+1)%3 → bounce through vertex (exit_face+2)%3
//   - Entry at vertex V, exit on face (V+1)%3 → no bounce (path crosses interior naturally)
//
// The "opposite vertex" for face F is the vertex not touching that face:
//   Face 0 (v0-v1) → opposite vertex is v2 (index 2)
//   Face 1 (v1-v2) → opposite vertex is v0 (index 0)
//   Face 2 (v2-v0) → opposite vertex is v1 (index 1)
//
// =================================================================================================

typedef struct {
  int needs_bounce;        // 1 if light should bounce through a vertex, 0 for direct path
  int bounce_vertex_idx;   // Which vertex to bounce through: 0=v0, 1=v1, 2=v2, -1=none
  float bounce_x, bounce_y; // Bounce point coordinates (valid only if needs_bounce=1)
} BounceInfo;

// Classify a hit point on a prism edge as either a face or vertex location.
//
// Parameters:
//   edge_idx: Which edge was hit (0=right v0→v1, 1=bottom v1→v2, 2=left v2→v0)
//   u: Parametric position along edge (0.0=start vertex, 1.0=end vertex)
//
// Returns:
//   0-2: Point is on a face (0=right, 1=bottom, 2=left)
//   3-5: Point is at a vertex (3=v0, 4=v1, 5=v2)
//
// Vertex detection uses a scale-independent threshold: if u < 0.05 or u > 0.95,
// the point is considered to be at the start or end vertex of the edge.
// This 5% threshold provides stability against floating-point variation at 60fps.
static int classify_edge_position(int edge_idx, float u) {
  // Guard against invalid inputs (e.g., from failed ray intersection)
  if (edge_idx < 0 || edge_idx > 2) return -1;

  // Threshold: within 5% of edge length counts as "at vertex"
  // Increased from 2% to provide stability margin for floating-point variation
  // during 60fps animation (fixes glitch at 08:00-08:01)
  const float VERTEX_THRESHOLD = 0.05f;

  if (u < VERTEX_THRESHOLD) {
    // At start vertex of edge: edge 0→v0, edge 1→v1, edge 2→v2
    return 3 + edge_idx;
  } else if (u > 1.0f - VERTEX_THRESHOLD) {
    // At end vertex of edge: edge 0→v1, edge 1→v2, edge 2→v0
    return 3 + ((edge_idx + 1) % 3);
  } else {
    // On the face (not at a vertex)
    return edge_idx;
  }
}

// Compute whether a light ray needs to bounce through a vertex to illuminate the prism interior.
//
// Parameters:
//   entry_edge: Which edge the ray entered through (from RayHit.edge_idx)
//   entry_u: Parametric position along entry edge (from RayHit.u)
//   hour_angle: Current hour hand angle (determines exit direction)
//   prism: The prism geometry (needed for bounce point coordinates)
//
// The bounce decision is based on comparing entry and exit faces:
//   - If entry and exit are on the same face, the ray would hug that edge → bounce needed
//   - If entry is at a vertex, bounce unless exit is on the "opposite" face (the one not
//     touching that vertex)
//
// IMPORTANT: We use find_prism_exit_from_center to determine the exit edge instead of
// angle-based determination. This ensures consistency with the actual rendered geometry,
// especially at vertex boundaries where angle-based methods can disagree with ray-casting.
static BounceInfo compute_bounce_info(
  int entry_edge,
  float entry_u,
  float hour_angle,
  const Prism* prism
) {
  BounceInfo info = {0, -1, 0.0f, 0.0f};

  // Compute prism center from vertices
  float cx = (prism->vertices[0] + prism->vertices[2] + prism->vertices[4]) / 3.0f;
  float cy = (prism->vertices[1] + prism->vertices[3] + prism->vertices[5]) / 3.0f;

  // Get actual exit edge from geometry (not angle-based approximation).
  // This ensures the bounce decision matches the rendered exit point.
  RayHit exit_hit = find_prism_exit_from_center(cx, cy, hour_angle, prism);
  if (!exit_hit.hit) return info;  // No valid exit found, no bounce needed

  int entry_location = classify_edge_position(entry_edge, entry_u);
  int exit_location = classify_edge_position(exit_hit.edge_idx, exit_hit.u);

  int needs_bounce = 0;
  int bounce_idx = -1;

  if (entry_location >= 3) {
    // Entry at a vertex (3=v0, 4=v1, 5=v2)
    int vertex_idx = entry_location - 3;

    if (vertex_idx == 0) {
      // Entry at v0: bounce if exit is at/near v0 (on face 0, face 2, or vertex v0).
      // These paths would hug the edge. At other times (e.g., 04:00 with exit at v1),
      // the direct path through the interior is valid.
      int exit_touches_v0 = (exit_location == 0 || exit_location == 2 || exit_location == 3);
      if (exit_touches_v0) {
        // Use direction sign for robust tie-break (avoids angle wrap issues).
        // dx >= 0 means pointing right (face 0 side) → bounce through v2.
        // dx < 0 means pointing left (face 2 side) → bounce through v1.
        float dx = cosf_approx(hour_angle);
        bounce_idx = (dx >= 0.0f) ? 2 : 1;
        needs_bounce = 1;
      }
    } else {
      // Entry at v1 or v2 - bounce unless exit touches opposite face
      int opposite_face = (vertex_idx + 1) % 3;

      int exit_touches_opposite = 0;
      if (exit_location >= 3) {
        // Exit at vertex - vertex V touches face V and face (V+2)%3
        int exit_vertex = exit_location - 3;
        exit_touches_opposite = (exit_vertex == opposite_face) ||
                                ((exit_vertex + 2) % 3 == opposite_face);
      } else {
        // Exit on a face
        exit_touches_opposite = (exit_location == opposite_face);
      }

      if (!exit_touches_opposite) {
        needs_bounce = 1;
        bounce_idx = (exit_hit.edge_idx + 2) % 3;
      }
    }
  } else {
    // Entry on a face (0=right, 1=bottom, 2=left)
    int same_face_exit = (exit_location < 3) && (exit_location == entry_location);

    if (same_face_exit) {
      // Same face entry/exit: bounce through opposite vertex
      needs_bounce = 1;
      bounce_idx = (entry_location + 2) % 3;
    } else if (exit_location == 3) {
      // Exit at vertex v0: if entry is on a face touching v0 (face 0 or 2),
      // the direct path is too short - bounce through v1 or v2.
      int entry_touches_v0 = (entry_location == 0 || entry_location == 2);

      if (entry_touches_v0) {
        // Use direction sign for robust tie-break (avoids angle wrap issues).
        // dx >= 0 means pointing right (face 0 side) → bounce through v2.
        // dx < 0 means pointing left (face 2 side) → bounce through v1.
        float dx = cosf_approx(hour_angle);
        bounce_idx = (dx >= 0.0f) ? 2 : 1;
        needs_bounce = 1;
      }
    }
  }

  if (needs_bounce) {
    info.needs_bounce = 1;
    info.bounce_vertex_idx = bounce_idx;
    info.bounce_x = prism->vertices[bounce_idx * 2];
    info.bounce_y = prism->vertices[bounce_idx * 2 + 1];
  }

  return info;
}
