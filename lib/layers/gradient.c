// =================================================================================================
// Gradient Layer Implementation
// =================================================================================================
// Renders smooth rainbow gradient fills using OkLab color space for perceptually uniform
// color transitions. This implements the "filled rainbow" effect seen in the album cover.

#include "layers/gradient.h"
#include "fastmath.h"
#include "geometry/prism.h"

// =================================================================================================
// Color Palette Definitions
// =================================================================================================
// Palette colors in sRGB (0-255). These match the palettes in palette.h.

typedef enum {
  GRADIENT_PALETTE_OKLCH_BALANCED = 0,
  GRADIENT_PALETTE_SATURATED = 1,
  GRADIENT_PALETTE_SPECTRAL = 2,
  GRADIENT_PALETTE_NEON = 3,
  GRADIENT_PALETTE_MUTED = 4,
  GRADIENT_PALETTE_EINK_PURE = 5,
  GRADIENT_PALETTE_EINK_DITHER = 6,
  GRADIENT_PALETTE_EINK_FULL = 7,
  GRADIENT_PALETTE_ALBUM_COVER = 8,
  GRADIENT_PALETTE_SPECTRA6 = 9,
  GRADIENT_PALETTE_COUNT
} GradientPaletteId;

static const unsigned char PALETTE_COLORS[GRADIENT_PALETTE_COUNT][GRADIENT_NUM_BANDS][3] = {
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
static GradientOkLab linear_to_oklab(float r, float g, float b) {
  // Linear RGB to LMS (cone responses)
  float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
  float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
  float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;

  // Cube root (perceptual nonlinearity)
  float lp = cbrtf_impl(l);
  float mp = cbrtf_impl(m);
  float sp = cbrtf_impl(s);

  // LMS' to OkLab
  GradientOkLab lab;
  lab.L = 0.2104542553f * lp + 0.7936177850f * mp - 0.0040720468f * sp;
  lab.a = 1.9779984951f * lp - 2.4285922050f * mp + 0.4505937099f * sp;
  lab.b = 0.0259040371f * lp + 0.7827717662f * mp - 0.8086757660f * sp;
  return lab;
}

// Convert OkLab to linear RGB
static GradientRGBLinear oklab_to_linear(GradientOkLab lab) {
  // OkLab to LMS'
  float lp = lab.L + 0.3963377774f * lab.a + 0.2158037573f * lab.b;
  float mp = lab.L - 0.1055613458f * lab.a - 0.0638541728f * lab.b;
  float sp = lab.L - 0.0894841775f * lab.a - 1.2914855480f * lab.b;

  // Cube (inverse of cube root)
  float l = lp * lp * lp;
  float m = mp * mp * mp;
  float s = sp * sp * sp;

  // LMS to linear RGB
  GradientRGBLinear rgb;
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
// Palette Cache Management
// =================================================================================================

void gradient_init_palette_cache(GradientPaletteCache *cache, int palette) {
  if (cache->initialized && cache->palette == palette) {
    return; // Already initialized with this palette
  }

  // Clamp palette to valid range
  if (palette < 0 || palette >= GRADIENT_PALETTE_COUNT) {
    palette = 0;
  }

  for (int i = 0; i < GRADIENT_NUM_BANDS; i++) {
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

GradientRGBLinear gradient_interpolate_color(const GradientPaletteCache *cache, float t) {
  // Handle extrapolation beyond visible spectrum
  if (t < 0.0f) {
    // Extrapolate toward infrared (darker, deeper red)
    GradientOkLab lab_infrared =
        linear_to_oklab(srgb_to_linear_f(140), srgb_to_linear_f(0), srgb_to_linear_f(0));
    GradientOkLab lab_red = cache->oklab[0];

    float frac = -t;
    if (frac > 1.0f)
      frac = 1.0f;

    GradientOkLab lab_interp;
    lab_interp.L = lab_red.L + frac * (lab_infrared.L - lab_red.L);
    lab_interp.a = lab_red.a + frac * (lab_infrared.a - lab_red.a);
    lab_interp.b = lab_red.b + frac * (lab_infrared.b - lab_red.b);
    return oklab_to_linear(lab_interp);
  }

  if (t > 1.0f) {
    // Extrapolate toward ultraviolet (deeper magenta/purple)
    GradientOkLab lab_ultraviolet =
        linear_to_oklab(srgb_to_linear_f(80), srgb_to_linear_f(0), srgb_to_linear_f(120));
    GradientOkLab lab_violet = cache->oklab[GRADIENT_NUM_BANDS - 1];

    float frac = t - 1.0f;
    if (frac > 1.0f)
      frac = 1.0f;

    GradientOkLab lab_interp;
    lab_interp.L = lab_violet.L + frac * (lab_ultraviolet.L - lab_violet.L);
    lab_interp.a = lab_violet.a + frac * (lab_ultraviolet.a - lab_violet.a);
    lab_interp.b = lab_violet.b + frac * (lab_ultraviolet.b - lab_violet.b);
    return oklab_to_linear(lab_interp);
  }

  // Map t to band index: t=0 -> band 0 (red), t=1 -> band 6 (violet)
  float scaled = t * (float)(GRADIENT_NUM_BANDS - 1);
  int band_lo = (int)scaled;
  int band_hi = band_lo + 1;

  // Clamp to valid range
  if (band_hi >= GRADIENT_NUM_BANDS)
    band_hi = GRADIENT_NUM_BANDS - 1;

  // Interpolation factor within the band
  float frac = scaled - (float)band_lo;

  // Interpolate in OkLab space
  GradientOkLab lab_lo = cache->oklab[band_lo];
  GradientOkLab lab_hi = cache->oklab[band_hi];

  GradientOkLab lab_interp;
  lab_interp.L = lab_lo.L + frac * (lab_hi.L - lab_lo.L);
  lab_interp.a = lab_lo.a + frac * (lab_hi.a - lab_lo.a);
  lab_interp.b = lab_lo.b + frac * (lab_hi.b - lab_lo.b);

  return oklab_to_linear(lab_interp);
}

// =================================================================================================
// Gradient Fill
// =================================================================================================

void gradient_draw_continuous(float *fb, int width, int height, GradientMode mode, float origin_x,
                              float origin_y, float cx, float cy, float radius, float angle_start,
                              float angle_end, const Prism *prism, float intensity,
                              int reverse_spectrum, const GradientPaletteCache *cache) {
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

  if (mode == GRADIENT_MODE_INTERNAL) {
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

      if (mode == GRADIENT_MODE_EXTERNAL) {
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
      float t_color = (t * (float)GRADIENT_NUM_BANDS - 0.5f) / (float)(GRADIENT_NUM_BANDS - 1);

      if (reverse_spectrum)
        t_color = 1.0f - t_color;

      // Interpolate color
      GradientRGBLinear color = gradient_interpolate_color(cache, t_color);

      // Additive blend
      int idx = (y * width + x) * 4;
      fb[idx] += color.r * intensity;
      fb[idx + 1] += color.g * intensity;
      fb[idx + 2] += color.b * intensity;
    }
  }
}

// =================================================================================================
// Layer Interface
// =================================================================================================
// Note: The gradient layer is integrated with the rays layer since it depends on ray path
// computation. This render function is provided for testing purposes.

static void layer_gradient_render(const RenderContext *ctx) {
  // Gradient rendering requires ray path data which is computed by the rays layer.
  // This stub exists for interface compatibility. In practice, gradient_draw_continuous
  // is called from within the rays layer after ray paths are computed.
  (void)ctx;
}

// Layer descriptor
const Layer LAYER_GRADIENT = {.name = "gradient", .render = layer_gradient_render};
