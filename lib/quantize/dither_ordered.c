#include "quantize/dither_ordered.h"
#include "fastmath.h"
#include "quantize/direct.h"

// =================================================================================================
// Bayer Matrices
// =================================================================================================
// Threshold matrices normalized to [-0.5, 0.5] range.
// Values are stored as (raw_value / n² - 0.5) where n is the matrix size.

// 2x2 Bayer matrix (4 threshold levels)
// Raw values: 0 2 / 3 1
static const float BAYER_2X2[2][2] = {
    {-0.5f, 0.0f},  // (0/4 - 0.5), (2/4 - 0.5)
    {0.25f, -0.25f} // (3/4 - 0.5), (1/4 - 0.5)
};

// 4x4 Bayer matrix (16 threshold levels)
// clang-format off
static const float BAYER_4X4[4][4] = {
    {-0.5f,      0.0f,       -0.375f,    0.125f   }, //  0,  8,  2, 10
    { 0.25f,    -0.25f,       0.375f,   -0.125f   }, // 12,  4, 14,  6
    {-0.3125f,   0.1875f,    -0.4375f,   0.0625f  }, //  3, 11,  1,  9
    { 0.4375f,  -0.0625f,     0.3125f,  -0.1875f  }  // 15,  7, 13,  5
};
// clang-format on

// 8x8 Bayer matrix (64 threshold levels)
// clang-format off
static const float BAYER_8X8[8][8] = {
    {-0.5f,       0.0f,      -0.375f,     0.125f,    -0.46875f,   0.03125f,  -0.34375f,   0.15625f },
    { 0.25f,     -0.25f,      0.375f,    -0.125f,     0.28125f,  -0.21875f,   0.40625f,  -0.09375f },
    {-0.3125f,    0.1875f,   -0.4375f,    0.0625f,   -0.28125f,   0.21875f,  -0.40625f,   0.09375f },
    { 0.4375f,   -0.0625f,    0.3125f,   -0.1875f,    0.46875f,  -0.03125f,   0.34375f,  -0.15625f },
    {-0.453125f,  0.046875f, -0.328125f,  0.171875f, -0.484375f,  0.015625f, -0.359375f,  0.140625f},
    { 0.296875f, -0.203125f,  0.421875f, -0.078125f,  0.265625f, -0.234375f,  0.390625f, -0.109375f},
    {-0.265625f,  0.234375f, -0.390625f,  0.109375f, -0.296875f,  0.203125f, -0.421875f,  0.078125f},
    { 0.484375f, -0.015625f,  0.359375f, -0.140625f,  0.453125f, -0.046875f,  0.328125f, -0.171875f}
};
// clang-format on

// =================================================================================================
// Cache Management
// =================================================================================================

int dither_ordered_init_cache(DitherOrderedCache *cache, const DitherRGB *palette,
                              int palette_count) {
  if (!cache || !palette || palette_count <= 0)
    return -1;
  if (palette_count > cache->palette_capacity)
    return -1;

  // Check if we can skip recomputation (same palette pointer and count)
  if (cache->last_palette == palette && cache->last_palette_count == palette_count) {
    return 0; // Cache is still valid
  }

  // Convert palette to OkLab
  for (int i = 0; i < palette_count; i++) {
    float r = dither_srgb_to_linear(palette[i].r);
    float g = dither_srgb_to_linear(palette[i].g);
    float b = dither_srgb_to_linear(palette[i].b);
    cache->palette_oklab[i] = dither_linear_to_oklab(r, g, b);
  }

  cache->last_palette = palette;
  cache->last_palette_count = palette_count;
  return 0;
}

// =================================================================================================
// Threshold Lookup
// =================================================================================================

static inline float get_threshold_2x2(int x, int y) { return BAYER_2X2[y & 1][x & 1]; }

static inline float get_threshold_4x4(int x, int y) { return BAYER_4X4[y & 3][x & 3]; }

static inline float get_threshold_8x8(int x, int y) { return BAYER_8X8[y & 7][x & 7]; }

// =================================================================================================
// Ordered Dithering Implementation
// =================================================================================================

int dither_ordered_apply(const float *float_fb, uint8_t *out_fb, int width, int height,
                         const DitherOrderedConfig *config, DitherOrderedCache *cache) {
  // Validate inputs
  if (!float_fb || !out_fb || !config || !cache)
    return -1;
  if (!config->palette || config->palette_count <= 0)
    return -1;
  if (width <= 0 || height <= 0)
    return -1;
  if (config->palette_count > cache->palette_capacity)
    return -1;

  // Initialize cache if palette changed
  if (dither_ordered_init_cache(cache, config->palette, config->palette_count) != 0) {
    return -1;
  }

  const DitherRGB *palette = config->palette;
  int palette_count = config->palette_count;
  float spread = clampf(config->spread, 0.0f, 1.0f);
  float chroma_weight = config->chroma_weight;

  // Select threshold function based on matrix type
  float (*get_threshold)(int, int);
  switch (config->matrix) {
  case DITHER_BAYER_4X4:
    get_threshold = get_threshold_4x4;
    break;
  case DITHER_BAYER_8X8:
    get_threshold = get_threshold_8x8;
    break;
  case DITHER_BAYER_2X2:
  default:
    get_threshold = get_threshold_2x2;
    break;
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int i = (y * width + x) * 4;

      // Get input pixel in linear RGB
      float r = clampf(float_fb[i], 0.0f, 1.0f);
      float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
      float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      // Convert to OkLab
      DitherOkLab color = dither_linear_to_oklab(r, g, b);

      // Get threshold from Bayer matrix and apply spread
      float threshold = get_threshold(x, y) * spread;

      // Apply threshold to lightness
      // Clamp to valid L range [0, 1]
      color.L = clampf(color.L + threshold, 0.0f, 1.0f);

      // Find closest palette color
      int idx =
          dither_find_closest_color(color, cache->palette_oklab, palette_count, chroma_weight);

      // Output the quantized color
      out_fb[i] = palette[idx].r;
      out_fb[i + 1] = palette[idx].g;
      out_fb[i + 2] = palette[idx].b;
      out_fb[i + 3] = round_f_to_u8(a * 255.0f);
    }
  }

  return 0;
}
