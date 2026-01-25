#include "quantize/dither.h"
#include "fastmath.h"

// =================================================================================================
// Palette Definitions
// =================================================================================================

// Pure RGB palette for dithering (ideal target colors)
const DitherRGB DITHER_PALETTE_IDEAL[DITHER_PALETTE_IDEAL_COUNT] = {
    {0, 0, 0},       // 0: Black
    {255, 255, 255}, // 1: White
    {255, 255, 0},   // 2: Yellow
    {255, 0, 0},     // 3: Red
    {0, 0, 255},     // 4: Blue
    {0, 255, 0},     // 5: Green
};

// Spectra 6 palette from Pimoroni Inky library (Inky Impression 13.3")
// Source: https://github.com/pimoroni/inky
const DitherRGB DITHER_PALETTE_SPECTRA6_INKY[DITHER_PALETTE_SPECTRA6_INKY_COUNT] = {
    {0, 0, 0},       // 0: Black
    {161, 164, 165}, // 1: Gray (device white appears grayish)
    {208, 190, 71},  // 2: Gold/Yellow
    {156, 72, 75},   // 3: Burgundy/Red
    {61, 59, 94},    // 4: Dark Blue
    {58, 91, 70},    // 5: Forest Green
};

// Spectra 6 palette from EDP Optimize (measured values)
// Source: https://github.com/Utzel-Butzel/epdoptimize
const DitherRGB DITHER_PALETTE_SPECTRA6_EPDOPT[DITHER_PALETTE_SPECTRA6_EPDOPT_COUNT] = {
    {25, 30, 33},    // 0: Black (#191E21)
    {232, 232, 232}, // 1: White (#e8e8e8)
    {239, 222, 68},  // 2: Yellow (#efde44)
    {178, 19, 24},   // 3: Red (#b21318)
    {33, 87, 186},   // 4: Blue (#2157ba)
    {18, 95, 32},    // 5: Green (#125f20)
};

// =================================================================================================
// Constants
// =================================================================================================

// Large float value for distance initialization
#define MAX_DISTANCE 3.4e38f

// =================================================================================================
// Color Space Conversions
// =================================================================================================

// Convert sRGB (0-255) to linear (0.0-1.0)
float dither_srgb_to_linear(uint8_t srgb) {
  float s = (float)srgb / 255.0f;
  if (s <= 0.04045f) {
    return s / 12.92f;
  }
  return fast_powf((s + 0.055f) / 1.055f, 2.4f);
}

// Convert linear RGB to OkLab
DitherOkLab dither_linear_to_oklab(float r, float g, float b) {
  // Linear RGB to LMS (cone responses)
  float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
  float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
  float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;

  // Cube root (perceptual nonlinearity)
  float lp = cbrtf_impl(l);
  float mp = cbrtf_impl(m);
  float sp = cbrtf_impl(s);

  // LMS' to OkLab
  DitherOkLab lab;
  lab.L = 0.2104542553f * lp + 0.7936177850f * mp - 0.0040720468f * sp;
  lab.a = 1.9779984951f * lp - 2.4285922050f * mp + 0.4505937099f * sp;
  lab.b = 0.0259040371f * lp + 0.7827717662f * mp - 0.8086757660f * sp;
  return lab;
}

// =================================================================================================
// OkLab Distance Functions
// =================================================================================================

// Compute OkLab chroma (saturation metric)
float dither_oklab_chroma(DitherOkLab color) {
  return sqrtf_impl(color.a * color.a + color.b * color.b);
}

// OkLab weighted distance squared
// chroma_weight = 1.0: L weighted 2x (default, good for general images)
// chroma_weight = 2.0: Equal L and chroma weighting (better for rainbows)
// chroma_weight = 4.0: Chroma weighted 2x (strongly prioritizes hue matching)
float dither_oklab_distance_sq(DitherOkLab a, DitherOkLab b, float chroma_weight) {
  float d_l = a.L - b.L;
  float da = a.a - b.a;
  float db = a.b - b.b;
  // Clamp to valid range (0.5-4.0) to avoid division issues
  float cw = clampf(chroma_weight, 0.5f, 4.0f);
  // Inverse relationship: as chroma_weight increases, l_weight decreases
  float l_weight = 2.0f / cw;
  return l_weight * d_l * d_l + cw * (da * da + db * db);
}

// Find closest palette color index using OkLab distance
int dither_find_closest_color(DitherOkLab color, const DitherOkLab *palette, int palette_count,
                              float chroma_weight) {
  int best_idx = 0;
  float best_dist = MAX_DISTANCE;

  for (int i = 0; i < palette_count; i++) {
    float dist = dither_oklab_distance_sq(color, palette[i], chroma_weight);
    if (dist < best_dist) {
      best_dist = dist;
      best_idx = i;
    }
  }

  return best_idx;
}
