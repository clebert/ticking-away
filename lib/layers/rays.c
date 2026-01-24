// =================================================================================================
// Rays Layer Implementation
// =================================================================================================
// Renders light rays through a prism, creating the iconic rainbow refraction effect.

#include "layers/rays.h"
#include "config.h"
#include "draw/line.h"
#include "fastmath.h"
#include "geometry/intersect.h"
#include "geometry/prism.h"
#include "kernels/kernel.h"

// =================================================================================================
// Constants
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)                 // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f)               // 30 degrees per hour
#define MAX_SPREAD_RAD (30.0f * PI / 180.0f) // Maximum spread in radians
#define SPREAD_EPSILON 0.001f                // Threshold for treating spread as zero

// Edge margin factor for extending gradient beyond visible rays into IR/UV zones
#define EDGE_MARGIN_FACTOR (0.5f / (float)(RAYS_NUM_BANDS - 1))

// Vertex detection threshold for bounce logic (see bounce.h for derivation)
#define VERTEX_THRESHOLD 0.0014f

// =================================================================================================
// Color Palette Definitions
// =================================================================================================
// Palette colors in sRGB (0-255). These match the palettes in palette.h.

typedef enum {
  RAYS_PALETTE_OKLCH_BALANCED,
  RAYS_PALETTE_SATURATED,
  RAYS_PALETTE_SPECTRAL,
  RAYS_PALETTE_NEON,
  RAYS_PALETTE_MUTED,
  RAYS_PALETTE_EINK_PURE,
  RAYS_PALETTE_EINK_DITHER,
  RAYS_PALETTE_EINK_FULL,
  RAYS_PALETTE_ALBUM_COVER,
  RAYS_PALETTE_SPECTRA6,
  RAYS_PALETTE_COUNT
} RaysPaletteId;

static const unsigned char PALETTE_COLORS[RAYS_PALETTE_COUNT][RAYS_NUM_BANDS][3] = {
    // PALETTE_OKLCH_BALANCED (friendly, even OkLCH hue spacing)
    {
        {255, 64, 64},  // Red
        {255, 160, 0},  // Orange
        {220, 220, 0},  // Yellow
        {0, 200, 80},   // Green
        {0, 180, 220},  // Cyan
        {80, 100, 255}, // Blue
        {180, 80, 255}  // Violet
    },
    // PALETTE_SATURATED
    {{255, 0, 0},
     {255, 128, 0},
     {255, 255, 0},
     {0, 255, 0},
     {0, 255, 255},
     {0, 0, 255},
     {128, 0, 255}},
    // PALETTE_SPECTRAL
    {{255, 0, 0},
     {255, 127, 0},
     {255, 255, 0},
     {0, 255, 0},
     {0, 127, 255},
     {0, 0, 255},
     {139, 0, 255}},
    // PALETTE_NEON
    {{255, 20, 80},
     {255, 100, 0},
     {200, 255, 0},
     {0, 255, 100},
     {0, 200, 255},
     {50, 50, 255},
     {200, 0, 255}},
    // PALETTE_MUTED
    {{200, 80, 80},
     {200, 140, 70},
     {180, 180, 80},
     {70, 160, 100},
     {80, 150, 180},
     {100, 110, 200},
     {150, 100, 200}},
    // PALETTE_EINK_PURE
    {{255, 0, 0}, {255, 255, 0}, {255, 255, 0}, {0, 255, 0}, {0, 255, 0}, {0, 0, 255}, {0, 0, 255}},
    // PALETTE_EINK_DITHER
    {{255, 0, 0},
     {255, 176, 0},
     {255, 255, 0},
     {0, 255, 0},
     {0, 160, 255},
     {0, 0, 255},
     {0, 0, 255}},
    // PALETTE_EINK_FULL
    {{255, 0, 0},
     {255, 160, 0},
     {255, 255, 0},
     {0, 255, 0},
     {0, 180, 220},
     {0, 0, 255},
     {40, 0, 255}},
    // PALETTE_ALBUM_COVER
    {{200, 0, 0},
     {255, 140, 0},
     {255, 255, 0},
     {0, 220, 0},
     {0, 100, 255},
     {0, 0, 200},
     {60, 0, 180}},
    // PALETTE_SPECTRA6
    {{178, 19, 24},
     {220, 130, 35},
     {240, 220, 60},
     {70, 145, 55},
     {0, 140, 200},
     {30, 70, 160},
     {100, 30, 160}}};

// =================================================================================================
// Color Conversion Utilities
// =================================================================================================

// Convert sRGB (0-255) to linear (0.0-1.0) using proper sRGB transfer function
static float srgb_to_linear_f(unsigned char srgb) {
  float s = (float)srgb / 255.0f;
  if (s <= 0.04045f) {
    return s / 12.92f;
  }
  return fast_powf((s + 0.055f) / 1.055f, 2.4f);
}

// Convert linear RGB to OkLab
static RaysOkLab linear_to_oklab(float r, float g, float b) {
  // Linear RGB to LMS (cone responses)
  float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
  float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
  float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;

  // Cube root (perceptual nonlinearity)
  float lp = cbrtf_impl(l);
  float mp = cbrtf_impl(m);
  float sp = cbrtf_impl(s);

  // LMS' to OkLab
  RaysOkLab lab;
  lab.L = 0.2104542553f * lp + 0.7936177850f * mp - 0.0040720468f * sp;
  lab.a = 1.9779984951f * lp - 2.4285922050f * mp + 0.4505937099f * sp;
  lab.b = 0.0259040371f * lp + 0.7827717662f * mp - 0.8086757660f * sp;
  return lab;
}

// Convert OkLab to linear RGB
static RaysRGBLinear oklab_to_linear(RaysOkLab lab) {
  // OkLab to LMS'
  float lp = lab.L + 0.3963377774f * lab.a + 0.2158037573f * lab.b;
  float mp = lab.L - 0.1055613458f * lab.a - 0.0638541728f * lab.b;
  float sp = lab.L - 0.0894841775f * lab.a - 1.2914855480f * lab.b;

  // Cube (inverse of cube root)
  float l = lp * lp * lp;
  float m = mp * mp * mp;
  float s = sp * sp * sp;

  // LMS to linear RGB
  RaysRGBLinear rgb;
  rgb.r = 4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s;
  rgb.g = -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s;
  rgb.b = -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s;

  // Clamp to valid range
  if (rgb.r < 0.0f)
    rgb.r = 0.0f;
  if (rgb.g < 0.0f)
    rgb.g = 0.0f;
  if (rgb.b < 0.0f)
    rgb.b = 0.0f;

  return rgb;
}

// =================================================================================================
// Palette Cache Management (5.3a)
// =================================================================================================

void rays_init_palette_cache(RaysPaletteCache *cache, int palette) {
  if (cache->initialized && cache->palette == palette) {
    return; // Already initialized with this palette
  }

  // Clamp palette to valid range
  if (palette < 0 || palette >= RAYS_PALETTE_COUNT) {
    palette = 0;
  }

  for (int i = 0; i < RAYS_NUM_BANDS; i++) {
    // Convert sRGB to linear RGB
    cache->linear[i].r = srgb_to_linear_f(PALETTE_COLORS[palette][i][0]);
    cache->linear[i].g = srgb_to_linear_f(PALETTE_COLORS[palette][i][1]);
    cache->linear[i].b = srgb_to_linear_f(PALETTE_COLORS[palette][i][2]);

    // Also compute OkLab for gradient interpolation
    cache->oklab[i] = linear_to_oklab(cache->linear[i].r, cache->linear[i].g, cache->linear[i].b);
  }

  cache->palette = palette;
  cache->initialized = 1;
}

RaysRGBLinear rays_get_band_color(const RaysPaletteCache *cache, int band_idx) {
  if (band_idx < 0 || band_idx >= RAYS_NUM_BANDS) {
    RaysRGBLinear black = {0.0f, 0.0f, 0.0f};
    return black;
  }
  return cache->linear[band_idx];
}

// Interpolate rainbow color at position t using OkLab for perceptual uniformity
// t=0 is red, t=1 is violet, extrapolates beyond for IR/UV zones
RaysRGBLinear rays_interpolate_color(const RaysPaletteCache *cache, float t) {
  // Handle extrapolation beyond visible spectrum
  if (t < 0.0f) {
    // Extrapolate toward infrared (darker, deeper red)
    RaysOkLab lab_infrared =
        linear_to_oklab(srgb_to_linear_f(140), srgb_to_linear_f(0), srgb_to_linear_f(0));
    RaysOkLab lab_red = cache->oklab[0];

    float frac = -t;
    if (frac > 1.0f)
      frac = 1.0f;

    RaysOkLab lab_interp;
    lab_interp.L = lab_red.L + frac * (lab_infrared.L - lab_red.L);
    lab_interp.a = lab_red.a + frac * (lab_infrared.a - lab_red.a);
    lab_interp.b = lab_red.b + frac * (lab_infrared.b - lab_red.b);
    return oklab_to_linear(lab_interp);
  }

  if (t > 1.0f) {
    // Extrapolate toward ultraviolet (deeper magenta/purple)
    RaysOkLab lab_ultraviolet =
        linear_to_oklab(srgb_to_linear_f(80), srgb_to_linear_f(0), srgb_to_linear_f(120));
    RaysOkLab lab_violet = cache->oklab[RAYS_NUM_BANDS - 1];

    float frac = t - 1.0f;
    if (frac > 1.0f)
      frac = 1.0f;

    RaysOkLab lab_interp;
    lab_interp.L = lab_violet.L + frac * (lab_ultraviolet.L - lab_violet.L);
    lab_interp.a = lab_violet.a + frac * (lab_ultraviolet.a - lab_violet.a);
    lab_interp.b = lab_violet.b + frac * (lab_ultraviolet.b - lab_violet.b);
    return oklab_to_linear(lab_interp);
  }

  // Map t to band index: t=0 -> band 0 (red), t=1 -> band 6 (violet)
  float scaled = t * (float)(RAYS_NUM_BANDS - 1);
  int band_lo = (int)scaled;
  int band_hi = band_lo + 1;

  // Clamp to valid range
  if (band_hi >= RAYS_NUM_BANDS)
    band_hi = RAYS_NUM_BANDS - 1;

  // Interpolation factor within the band
  float frac = scaled - (float)band_lo;

  // Interpolate in OkLab space
  RaysOkLab lab_lo = cache->oklab[band_lo];
  RaysOkLab lab_hi = cache->oklab[band_hi];

  RaysOkLab lab_interp;
  lab_interp.L = lab_lo.L + frac * (lab_hi.L - lab_lo.L);
  lab_interp.a = lab_lo.a + frac * (lab_hi.a - lab_lo.a);
  lab_interp.b = lab_lo.b + frac * (lab_hi.b - lab_lo.b);

  return oklab_to_linear(lab_interp);
}

// =================================================================================================
// Bounce Detection (5.3b)
// =================================================================================================

// Classify a hit point on a prism edge as either face or vertex
// Returns: 0-2 for face, 3-5 for vertex (3=v0, 4=v1, 5=v2)
static int classify_edge_position(int edge_idx, float u) {
  if (edge_idx < 0 || edge_idx > 2)
    return -1;

  if (u < VERTEX_THRESHOLD) {
    // At start vertex: edge 0→v0, edge 1→v1, edge 2→v2
    return 3 + edge_idx;
  } else if (u > 1.0f - VERTEX_THRESHOLD) {
    // At end vertex: edge 0→v1, edge 1→v2, edge 2→v0
    return 3 + ((edge_idx + 1) % 3);
  } else {
    // On the face (not at a vertex)
    return edge_idx;
  }
}

// Compute bounce info - whether rays need to bounce through a vertex
typedef struct {
  int needs_bounce;
  int bounce_vertex_idx;
  float bounce_x, bounce_y;
} BounceInfo;

static BounceInfo compute_bounce_info(int entry_edge, float entry_u, float hour_angle,
                                      const Prism *prism) {
  BounceInfo info = {0, -1, 0.0f, 0.0f};

  if (entry_edge < 0 || entry_edge > 2)
    return info;

  // Compute prism center from vertices
  float v0x, v0y, v1x, v1y, v2x, v2y;
  prism_get_vertex(prism, 0, &v0x, &v0y);
  prism_get_vertex(prism, 1, &v1x, &v1y);
  prism_get_vertex(prism, 2, &v2x, &v2y);
  float cx = (v0x + v1x + v2x) / 3.0f;
  float cy = (v0y + v1y + v2y) / 3.0f;

  // Get actual exit edge from geometry
  RayHit exit_hit = prism_find_exit_from_center(cx, cy, hour_angle, prism);
  if (!exit_hit.hit)
    return info;

  int entry_location = classify_edge_position(entry_edge, entry_u);
  int exit_location = classify_edge_position(exit_hit.edge_idx, exit_hit.u);

  int needs_bounce = 0;
  int bounce_idx = -1;

  if (entry_location >= 3) {
    // Entry at a vertex
    int vertex_idx = entry_location - 3;

    if (vertex_idx == 0) {
      // Entry at v0
      int exit_touches_v0 = (exit_location == 0 || exit_location == 2 || exit_location == 3);
      if (exit_touches_v0) {
        float dx = cosf_approx(hour_angle);
        bounce_idx = (dx >= 0.0f) ? 2 : 1;
        needs_bounce = 1;
      }
    } else {
      // Entry at v1 or v2
      int opposite_face = (vertex_idx + 1) % 3;
      int exit_touches_opposite = 0;

      if (exit_location >= 3) {
        int exit_vertex = exit_location - 3;
        exit_touches_opposite =
            (exit_vertex == opposite_face) || ((exit_vertex + 2) % 3 == opposite_face);
      } else {
        exit_touches_opposite = (exit_location == opposite_face);
      }

      if (!exit_touches_opposite) {
        needs_bounce = 1;
        bounce_idx = (exit_hit.edge_idx + 2) % 3;
      }
    }
  } else {
    // Entry on a face
    int same_face_exit = (exit_location < 3) && (exit_location == entry_location);

    if (same_face_exit) {
      needs_bounce = 1;
      bounce_idx = (entry_location + 2) % 3;
    } else if (exit_location == 3) {
      // Exit at vertex v0
      int entry_touches_v0 = (entry_location == 0 || entry_location == 2);
      if (entry_touches_v0) {
        float dx = cosf_approx(hour_angle);
        bounce_idx = (dx >= 0.0f) ? 2 : 1;
        needs_bounce = 1;
      }
    }
  }

  if (needs_bounce && bounce_idx >= 0 && bounce_idx < 3) {
    info.needs_bounce = 1;
    info.bounce_vertex_idx = bounce_idx;
    prism_get_vertex(prism, bounce_idx, &info.bounce_x, &info.bounce_y);
  }

  return info;
}

// =================================================================================================
// Ray Path Computation (5.3b)
// =================================================================================================

// Compute exit angle for a given band index
static float compute_exit_angle(float hour_angle, float rainbow_spread, int band_idx) {
  // Centered spacing: t = (i + 0.5) / N
  float t = ((float)band_idx + 0.5f) / (float)RAYS_NUM_BANDS;
  float spread_rad = rainbow_spread * MAX_SPREAD_RAD;
  // Physical: t=0 (infrared) gets positive offset, t=1 (ultraviolet) gets negative
  float offset = (0.5f - t) * spread_rad;
  return hour_angle + offset;
}

RaysPaths rays_compute_paths(float cx, float cy, float radius, float entry_x, float entry_y,
                             float hour_angle, float rainbow_spread, const Prism *prism) {
  RaysPaths paths = {0};

  // Entry ray direction: toward center
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  // Find where entry ray hits prism
  RayHit prism_entry = prism_find_entry(entry_x, entry_y, entry_dx, entry_dy, prism);

  if (!prism_entry.hit) {
    paths.hits_prism = 0;
    return paths;
  }

  paths.hits_prism = 1;
  paths.entry_x = prism_entry.px;
  paths.entry_y = prism_entry.py;
  paths.entry_edge = prism_entry.edge_idx;
  paths.entry_u = prism_entry.u;

  // Clip incoming ray to circle
  float clip_x0, clip_y0, clip_x1, clip_y1;
  int has_clipped_entry =
      clip_segment_to_circle(entry_x, entry_y, prism_entry.px, prism_entry.py, cx, cy, radius,
                             &clip_x0, &clip_y0, &clip_x1, &clip_y1);

  if (has_clipped_entry) {
    paths.entry_ray.x0 = clip_x0;
    paths.entry_ray.y0 = clip_y0;
    paths.entry_ray.x1 = clip_x1;
    paths.entry_ray.y1 = clip_y1;
    paths.entry_ray.valid = 1;
  }

  // Compute bounce decision
  BounceInfo bounce = compute_bounce_info(prism_entry.edge_idx, prism_entry.u, hour_angle, prism);

  paths.needs_bounce = bounce.needs_bounce;
  paths.bounce_x = bounce.bounce_x;
  paths.bounce_y = bounce.bounce_y;

  // Compute boundary ray data for gradient rendering
  if (rainbow_spread > SPREAD_EPSILON) {
    paths.angle_first = compute_exit_angle(hour_angle, rainbow_spread, 0);
    paths.angle_last = compute_exit_angle(hour_angle, rainbow_spread, RAYS_NUM_BANDS - 1);

    RayHit exit_first = prism_find_exit_from_center(cx, cy, paths.angle_first, prism);
    RayHit exit_last = prism_find_exit_from_center(cx, cy, paths.angle_last, prism);

    if (exit_first.hit && exit_last.hit) {
      paths.exit_first_x = exit_first.px;
      paths.exit_first_y = exit_first.py;
      paths.exit_last_x = exit_last.px;
      paths.exit_last_y = exit_last.py;

      // Compute circle boundary intersections
      float ext_dir_first_x = cosf_approx(paths.angle_first);
      float ext_dir_first_y = sinf_approx(paths.angle_first);
      if (ray_circle_intersect(exit_first.px, exit_first.py, ext_dir_first_x, ext_dir_first_y, cx,
                               cy, radius, &paths.border_first_x, &paths.border_first_y)) {
        float ext_dir_last_x = cosf_approx(paths.angle_last);
        float ext_dir_last_y = sinf_approx(paths.angle_last);
        if (ray_circle_intersect(exit_last.px, exit_last.py, ext_dir_last_x, ext_dir_last_y, cx, cy,
                                 radius, &paths.border_last_x, &paths.border_last_y)) {
          paths.gradient_valid = 1;
        }
      }
    }
  }

  // Compute per-band paths
  for (int i = 0; i < RAYS_NUM_BANDS; i++) {
    RaysBandPath *band = &paths.bands[i];

    // Compute exit angle for this band
    band->exit_angle = compute_exit_angle(hour_angle, rainbow_spread, i);

    // Find where exit ray exits the prism
    RayHit prism_exit = prism_find_exit_from_center(cx, cy, band->exit_angle, prism);

    if (!prism_exit.hit) {
      continue;
    }

    band->prism_exit_x = prism_exit.px;
    band->prism_exit_y = prism_exit.py;
    band->internal_exit_x = prism_exit.px;
    band->internal_exit_y = prism_exit.py;

    // Internal path segments
    if (bounce.needs_bounce) {
      // Segment 1: entry → bounce
      band->internal_seg1.x0 = prism_entry.px;
      band->internal_seg1.y0 = prism_entry.py;
      band->internal_seg1.x1 = bounce.bounce_x;
      band->internal_seg1.y1 = bounce.bounce_y;
      band->internal_seg1.valid = 1;

      // Segment 2: bounce → exit
      band->internal_seg2.x0 = bounce.bounce_x;
      band->internal_seg2.y0 = bounce.bounce_y;
      band->internal_seg2.x1 = band->internal_exit_x;
      band->internal_seg2.y1 = band->internal_exit_y;
      band->internal_seg2.valid = 1;
    } else {
      // Direct path: entry → exit
      band->internal_seg1.x0 = prism_entry.px;
      band->internal_seg1.y0 = prism_entry.py;
      band->internal_seg1.x1 = band->internal_exit_x;
      band->internal_seg1.y1 = band->internal_exit_y;
      band->internal_seg1.valid = 1;
    }

    // Exit ray: from prism exit to circle edge
    float exit_dir_x = cosf_approx(band->exit_angle);
    float exit_dir_y = sinf_approx(band->exit_angle);

    float border_x, border_y;
    if (ray_circle_intersect(prism_exit.px, prism_exit.py, exit_dir_x, exit_dir_y, cx, cy, radius,
                             &border_x, &border_y)) {
      band->exit_ray.x0 = prism_exit.px;
      band->exit_ray.y0 = prism_exit.py;
      band->exit_ray.x1 = border_x;
      band->exit_ray.y1 = border_y;
      band->exit_ray.valid = 1;
    }
  }

  return paths;
}

// =================================================================================================
// Gradient Rendering
// =================================================================================================

typedef enum {
  GRADIENT_EXTERNAL, // Inside circle, outside prism
  GRADIENT_INTERNAL  // Inside prism only
} GradientMode;

// Draw continuous gradient fill with band-based color interpolation
static void draw_gradient_continuous(float *fb, int width, int height, GradientMode mode,
                                     float origin_x, float origin_y, float cx, float cy,
                                     float radius, float angle_start, float angle_end,
                                     const Prism *prism, float intensity, int reverse_spectrum,
                                     const RaysPaletteCache *palette) {
  float a1 = angle_start;
  float a2 = angle_end;
  while (a1 < 0)
    a1 += TAU;
  while (a1 >= TAU)
    a1 -= TAU;
  while (a2 < 0)
    a2 += TAU;
  while (a2 >= TAU)
    a2 -= TAU;

  float angle_diff = a2 - a1;
  if (angle_diff > PI)
    angle_diff -= TAU;
  if (angle_diff < -PI)
    angle_diff += TAU;

  float angle_span = angle_diff > 0 ? angle_diff : -angle_diff;
  if (angle_span < 0.001f || angle_span > PI)
    return;

  int reverse = (angle_diff < 0);
  if (reverse) {
    float tmp = a1;
    a1 = a2;
    a2 = tmp;
  }

  // Save original boundary for interpolation
  float a1_orig = a1;
  int wrap_around = (a1 > a2);

  // Expand acceptance range by epsilon
  float eps = 0.002f;
  a1 -= eps;
  a2 += eps;
  if (a1 < 0)
    a1 += TAU;
  if (a2 >= TAU)
    a2 -= TAU;

  int x_start = 0, x_end = width, y_start = 0, y_end = height;
  float radius_sq = radius * radius;

  // Get prism vertices
  float v0x, v0y, v1x, v1y, v2x, v2y;
  prism_get_vertex(prism, 0, &v0x, &v0y);
  prism_get_vertex(prism, 1, &v1x, &v1y);
  prism_get_vertex(prism, 2, &v2x, &v2y);

  if (mode == GRADIENT_INTERNAL) {
    float min_x = v0x < v1x ? (v0x < v2x ? v0x : v2x) : (v1x < v2x ? v1x : v2x);
    float max_x = v0x > v1x ? (v0x > v2x ? v0x : v2x) : (v1x > v2x ? v1x : v2x);
    float min_y = v0y < v1y ? (v0y < v2y ? v0y : v2y) : (v1y < v2y ? v1y : v2y);
    float max_y = v0y > v1y ? (v0y > v2y ? v0y : v2y) : (v1y > v2y ? v1y : v2y);

    x_start = (int)min_x;
    x_end = (int)max_x + 1;
    y_start = (int)min_y;
    y_end = (int)max_y + 1;

    if (x_start < 0)
      x_start = 0;
    if (y_start < 0)
      y_start = 0;
    if (x_end > width)
      x_end = width;
    if (y_end > height)
      y_end = height;
  }

  for (int y = y_start; y < y_end; y++) {
    float py = (float)y + 0.5f;
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;

      if (mode == GRADIENT_EXTERNAL) {
        float dx_circle = px - cx;
        float dy_circle = py - cy;
        if (dx_circle * dx_circle + dy_circle * dy_circle > radius_sq)
          continue;
        if (point_in_triangle(px, py, v0x, v0y, v1x, v1y, v2x, v2y))
          continue;
      } else {
        if (!point_in_triangle(px, py, v0x, v0y, v1x, v1y, v2x, v2y))
          continue;
      }

      float dx = px - origin_x;
      float dy = py - origin_y;
      float pixel_angle = atan2_approx(dy, dx);
      if (pixel_angle < 0)
        pixel_angle += TAU;

      float t;
      if (wrap_around) {
        if (pixel_angle < a1 && pixel_angle > a2)
          continue;
        if (pixel_angle >= a1_orig) {
          t = (pixel_angle - a1_orig) / angle_span;
        } else {
          t = (TAU - a1_orig + pixel_angle) / angle_span;
        }
      } else {
        if (pixel_angle < a1 || pixel_angle > a2)
          continue;
        t = (pixel_angle - a1_orig) / angle_span;
      }

      if (reverse)
        t = 1.0f - t;

      // Remap t for centered band spacing
      float t_color = (t * (float)RAYS_NUM_BANDS - 0.5f) / (float)(RAYS_NUM_BANDS - 1);

      if (reverse_spectrum)
        t_color = 1.0f - t_color;

      // Interpolate color
      RaysRGBLinear color = rays_interpolate_color(palette, t_color);

      // Additive blend
      int idx = (y * width + x) * 4;
      fb[idx] += color.r * intensity;
      fb[idx + 1] += color.g * intensity;
      fb[idx + 2] += color.b * intensity;
    }
  }
}

// =================================================================================================
// Ray Rendering (5.3c)
// =================================================================================================

static void render_rays(float *fb, int width, int height, float cx, float cy, float radius,
                        const RaysPaths *paths, const RayConfig *ray_config, float rainbow_spread,
                        const Prism *prism, const RaysPaletteCache *palette) {
  float ray_glow_width = ray_config->glow_width * radius;
  float ray_glow_intensity = ray_config->intensity;
  FalloffType ray_glow_falloff = ray_config->falloff;
  int gradient_fill = ray_config->gradient_fill;
  int reverse_spectrum = ray_config->reverse;

  // Get prism vertices for clipping
  float v0x, v0y, v1x, v1y, v2x, v2y;
  prism_get_vertex(prism, 0, &v0x, &v0y);
  prism_get_vertex(prism, 1, &v1x, &v1y);
  prism_get_vertex(prism, 2, &v2x, &v2y);
  float prism_verts[6] = {v0x, v0y, v1x, v1y, v2x, v2y};

  float circle_clip[3] = {cx, cy, radius};

  // Draw gradient fill between rainbow rays (when enabled and spread > 0)
  if (gradient_fill && paths->gradient_valid) {
    float gradient_intensity = 1.0f;

    // Compute angles from CENTER to where boundary rays hit CIRCLE
    float ext_angle_first = atan2_approx(paths->border_first_y - cy, paths->border_first_x - cx);
    float ext_angle_last = atan2_approx(paths->border_last_y - cy, paths->border_last_x - cx);

    // Extend gradient angles to include IR/UV zones
    float ray_span = ext_angle_last - ext_angle_first;
    if (ray_span > PI)
      ray_span -= TAU;
    if (ray_span < -PI)
      ray_span += TAU;
    float edge_margin = ray_span * EDGE_MARGIN_FACTOR;
    float ext_angle_infrared = ext_angle_first - edge_margin;
    float ext_angle_ultraviolet = ext_angle_last + edge_margin;

    // Draw external gradient (outside prism)
    draw_gradient_continuous(fb, width, height, GRADIENT_EXTERNAL, cx, cy, cx, cy, radius,
                             ext_angle_infrared, ext_angle_ultraviolet, prism, gradient_intensity,
                             reverse_spectrum, palette);

    // Draw internal gradient (inside prism)
    float grad_origin_x = paths->needs_bounce ? paths->bounce_x : paths->entry_x;
    float grad_origin_y = paths->needs_bounce ? paths->bounce_y : paths->entry_y;

    const RaysBandPath *first_band = &paths->bands[0];
    const RaysBandPath *last_band = &paths->bands[RAYS_NUM_BANDS - 1];

    float internal_angle_first = atan2_approx(first_band->internal_exit_y - grad_origin_y,
                                              first_band->internal_exit_x - grad_origin_x);
    float internal_angle_last = atan2_approx(last_band->internal_exit_y - grad_origin_y,
                                             last_band->internal_exit_x - grad_origin_x);

    float internal_ray_span = internal_angle_last - internal_angle_first;
    if (internal_ray_span > PI)
      internal_ray_span -= TAU;
    if (internal_ray_span < -PI)
      internal_ray_span += TAU;
    float internal_edge_margin = internal_ray_span * EDGE_MARGIN_FACTOR;
    float internal_angle_infrared = internal_angle_first - internal_edge_margin;
    float internal_angle_ultraviolet = internal_angle_last + internal_edge_margin;

    draw_gradient_continuous(fb, width, height, GRADIENT_INTERNAL, grad_origin_x, grad_origin_y, 0,
                             0, 0, // cx, cy, radius unused for internal mode
                             internal_angle_infrared, internal_angle_ultraviolet, prism,
                             gradient_intensity, reverse_spectrum, palette);
  }

  // Compute internal ray fade when gradient is enabled
  int draw_internal_colored_rays = 1;
  int draw_exit_rays = 1;
  int use_gradient_intensity = 0;

  if (gradient_fill && paths->gradient_valid) {
    draw_exit_rays = 0;
    use_gradient_intensity = 1;

    if (rainbow_spread > 0.99f) {
      draw_internal_colored_rays = 0;
    }
  }

  // Draw all rays per-band
  for (int i = 0; i < RAYS_NUM_BANDS; i++) {
    int color_idx = reverse_spectrum ? (RAYS_NUM_BANDS - 1 - i) : i;
    RaysRGBLinear color = rays_get_band_color(palette, color_idx);
    const RaysBandPath *band = &paths->bands[i];

    // Draw incoming ray (outside prism) - pure white
    if (paths->entry_ray.valid) {
      line_draw_glow(fb, width, height, paths->entry_ray.x0, paths->entry_ray.y0,
                     paths->entry_ray.x1, paths->entry_ray.y1, 1.0f, 1.0f, 1.0f, ray_glow_width,
                     ray_glow_intensity, ray_glow_falloff, nullptr, circle_clip, prism_verts);
    }

    // Draw internal path segments
    if (band->internal_seg1.valid) {
      if (paths->needs_bounce) {
        // Entry→bounce segment: pure white
        line_draw_glow(fb, width, height, band->internal_seg1.x0, band->internal_seg1.y0,
                       band->internal_seg1.x1, band->internal_seg1.y1, 1.0f, 1.0f, 1.0f,
                       ray_glow_width, ray_glow_intensity, ray_glow_falloff, prism_verts, nullptr,
                       nullptr);

        // Bounced path: bounce → exit (colored)
        if (band->internal_seg2.valid && draw_internal_colored_rays) {
          if (use_gradient_intensity) {
            line_draw_glow_gradient(fb, width, height, band->internal_seg2.x0,
                                    band->internal_seg2.y0, band->internal_seg2.x1,
                                    band->internal_seg2.y1, color.r, color.g, color.b,
                                    ray_glow_width, ray_glow_intensity, 0.0f, ray_glow_falloff,
                                    prism_verts, nullptr, nullptr);
          } else {
            line_draw_glow(fb, width, height, band->internal_seg2.x0, band->internal_seg2.y0,
                           band->internal_seg2.x1, band->internal_seg2.y1, color.r, color.g,
                           color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
                           prism_verts, nullptr, nullptr);
          }
        }
      } else {
        // Direct path: entry → exit (colored)
        if (draw_internal_colored_rays) {
          if (use_gradient_intensity) {
            line_draw_glow_gradient(fb, width, height, band->internal_seg1.x0,
                                    band->internal_seg1.y0, band->internal_seg1.x1,
                                    band->internal_seg1.y1, color.r, color.g, color.b,
                                    ray_glow_width, ray_glow_intensity, 0.0f, ray_glow_falloff,
                                    prism_verts, nullptr, nullptr);
          } else {
            line_draw_glow(fb, width, height, band->internal_seg1.x0, band->internal_seg1.y0,
                           band->internal_seg1.x1, band->internal_seg1.y1, color.r, color.g,
                           color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
                           prism_verts, nullptr, nullptr);
          }
        }
      }
    }

    // Draw exit ray (from prism exit to circle edge)
    if (band->exit_ray.valid && draw_exit_rays) {
      line_draw_glow(fb, width, height, band->exit_ray.x0, band->exit_ray.y0, band->exit_ray.x1,
                     band->exit_ray.y1, color.r, color.g, color.b, ray_glow_width,
                     ray_glow_intensity, ray_glow_falloff, nullptr, circle_clip, prism_verts);
    }
  }
}

// =================================================================================================
// Layer Interface (5.3d)
// =================================================================================================

void layer_rays_render(const RenderContext *ctx) {
  // Validate required context fields
  if (!ctx->fb || !ctx->prism || !ctx->ray_config || !ctx->prism_config) {
    return;
  }

  float cx = ctx->cx;
  float cy = ctx->cy;
  float radius = ctx->radius;
  float time_minutes = ctx->time_minutes;

  // Convert time_minutes (0-720) to hour and minute components
  // time_minutes = hour * 60 + minute, where hour is 0-11
  float hours_f = time_minutes / 60.0f;
  int hours = (int)hours_f % 12;
  float minutes = time_minutes - (float)(hours * 60);
  if (minutes < 0)
    minutes = 0;
  if (minutes >= 60)
    minutes = 59.9999f;

  // Calculate minute position (light source on circle edge)
  float minute_angle = ANGLE_0 + (minutes / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  // Calculate hour angle (target) with minute interpolation
  float hour_angle = ANGLE_0 + ((float)hours / 12.0f) * TAU + (minutes / 60.0f) * HOUR_ARC;

  // Get rainbow spread from prism config
  float rainbow_spread = ctx->prism_config->rainbow_spread;

  // Initialize palette cache
  RaysPaletteCache palette_cache;
  palette_cache.initialized = 0;
  rays_init_palette_cache(&palette_cache, ctx->ray_config->palette);

  // Compute ray paths
  RaysPaths paths =
      rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle, rainbow_spread, ctx->prism);

  if (!paths.hits_prism) {
    // Ray doesn't hit prism - nothing to render
    return;
  }

  // Render the rays
  render_rays(ctx->fb, ctx->width, ctx->height, cx, cy, radius, &paths, ctx->ray_config,
              rainbow_spread, ctx->prism, &palette_cache);
}

// Layer descriptor
const Layer LAYER_RAYS = {.name = "rays", .render = layer_rays_render};
