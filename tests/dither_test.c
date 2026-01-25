// Test harness for dither quantizer

#include <stdint.h>

#include "quantize/dither.h"
#include "quantize/dither_error.h"
#include "quantize/dither_ordered.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: sRGB to Linear Conversion
// =================================================================================================

void test_srgb_to_linear_black(void) {
  TEST_BEGIN("srgb_to_linear_black");
  float result = dither_srgb_to_linear(0);
  ASSERT_NEAR(result, 0.0f, 0.0001f);
  TEST_END();
}

void test_srgb_to_linear_white(void) {
  TEST_BEGIN("srgb_to_linear_white");
  float result = dither_srgb_to_linear(255);
  ASSERT_NEAR(result, 1.0f, 0.001f);
  TEST_END();
}

void test_srgb_to_linear_mid_gray(void) {
  // sRGB 186 is approximately linear 0.5
  TEST_BEGIN("srgb_to_linear_mid_gray");
  float result = dither_srgb_to_linear(186);
  ASSERT_NEAR(result, 0.5f, 0.02f);
  TEST_END();
}

// =================================================================================================
// Test: Linear RGB to OkLab Conversion
// =================================================================================================

void test_linear_to_oklab_black(void) {
  TEST_BEGIN("linear_to_oklab_black");
  DitherOkLab lab = dither_linear_to_oklab(0.0f, 0.0f, 0.0f);
  ASSERT_NEAR(lab.L, 0.0f, 0.001f);
  ASSERT_NEAR(lab.a, 0.0f, 0.001f);
  ASSERT_NEAR(lab.b, 0.0f, 0.001f);
  TEST_END();
}

void test_linear_to_oklab_white(void) {
  TEST_BEGIN("linear_to_oklab_white");
  DitherOkLab lab = dither_linear_to_oklab(1.0f, 1.0f, 1.0f);
  ASSERT_NEAR(lab.L, 1.0f, 0.001f);
  ASSERT_NEAR(lab.a, 0.0f, 0.001f);
  ASSERT_NEAR(lab.b, 0.0f, 0.001f);
  TEST_END();
}

void test_linear_to_oklab_red(void) {
  TEST_BEGIN("linear_to_oklab_red");
  DitherOkLab lab = dither_linear_to_oklab(1.0f, 0.0f, 0.0f);
  // Red in OkLab has positive a (red-green) and positive b (yellow-blue)
  ASSERT_TRUE(lab.L > 0.5f);
  ASSERT_TRUE(lab.a > 0.1f); // Red has positive a
  TEST_END();
}

void test_linear_to_oklab_green(void) {
  TEST_BEGIN("linear_to_oklab_green");
  DitherOkLab lab = dither_linear_to_oklab(0.0f, 1.0f, 0.0f);
  // Green in OkLab has negative a
  ASSERT_TRUE(lab.L > 0.5f);
  ASSERT_TRUE(lab.a < -0.1f); // Green has negative a
  TEST_END();
}

void test_linear_to_oklab_blue(void) {
  TEST_BEGIN("linear_to_oklab_blue");
  DitherOkLab lab = dither_linear_to_oklab(0.0f, 0.0f, 1.0f);
  // Blue in OkLab has negative b
  ASSERT_TRUE(lab.L > 0.3f);
  ASSERT_TRUE(lab.b < -0.1f); // Blue has negative b
  TEST_END();
}

// =================================================================================================
// Test: OkLab Chroma (Saturation)
// =================================================================================================

void test_oklab_chroma_grayscale(void) {
  TEST_BEGIN("oklab_chroma_grayscale");
  DitherOkLab gray = {0.5f, 0.0f, 0.0f};
  float chroma = dither_oklab_chroma(gray);
  ASSERT_NEAR(chroma, 0.0f, 0.0001f);
  TEST_END();
}

void test_oklab_chroma_saturated(void) {
  TEST_BEGIN("oklab_chroma_saturated");
  DitherOkLab color = {0.5f, 0.2f, 0.1f};
  float chroma = dither_oklab_chroma(color);
  // sqrt(0.2^2 + 0.1^2) = sqrt(0.05) ≈ 0.224
  ASSERT_NEAR(chroma, 0.224f, 0.01f);
  TEST_END();
}

// =================================================================================================
// Test: OkLab Distance
// =================================================================================================

void test_oklab_distance_same_color(void) {
  TEST_BEGIN("oklab_distance_same_color");
  DitherOkLab a = {0.5f, 0.1f, -0.1f};
  float dist = dither_oklab_distance_sq(a, a, 1.0f);
  ASSERT_NEAR(dist, 0.0f, 0.0001f);
  TEST_END();
}

void test_oklab_distance_different_lightness(void) {
  TEST_BEGIN("oklab_distance_different_lightness");
  DitherOkLab a = {0.0f, 0.0f, 0.0f};
  DitherOkLab b = {1.0f, 0.0f, 0.0f};
  float dist = dither_oklab_distance_sq(a, b, 1.0f);
  // dL = 1.0, L_weight = 2.0, so dist = 2.0 * 1.0^2 = 2.0
  ASSERT_NEAR(dist, 2.0f, 0.01f);
  TEST_END();
}

void test_oklab_distance_chroma_weight(void) {
  TEST_BEGIN("oklab_distance_chroma_weight");
  DitherOkLab a = {0.5f, 0.0f, 0.0f};
  DitherOkLab b = {0.5f, 0.1f, 0.0f};

  // At chroma_weight=1.0: L_weight=2.0, dist = 1.0 * 0.01 = 0.01
  float dist1 = dither_oklab_distance_sq(a, b, 1.0f);

  // At chroma_weight=2.0: L_weight=1.0, dist = 2.0 * 0.01 = 0.02
  float dist2 = dither_oklab_distance_sq(a, b, 2.0f);

  ASSERT_TRUE(dist2 > dist1); // Higher chroma weight = bigger distance for chroma difference
  TEST_END();
}

// =================================================================================================
// Test: Palette Color Finding
// =================================================================================================

void test_find_closest_color_black(void) {
  TEST_BEGIN("find_closest_color_black");
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  dither_error_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab black = dither_linear_to_oklab(0.0f, 0.0f, 0.0f);
  int idx = dither_find_closest_color(black, cache.palette_oklab, DITHER_PALETTE_IDEAL_COUNT, 1.0f);
  ASSERT_EQ(idx, 0); // Black is at index 0
  TEST_END();
}

void test_find_closest_color_white(void) {
  TEST_BEGIN("find_closest_color_white");
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  dither_error_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab white = dither_linear_to_oklab(1.0f, 1.0f, 1.0f);
  int idx = dither_find_closest_color(white, cache.palette_oklab, DITHER_PALETTE_IDEAL_COUNT, 1.0f);
  ASSERT_EQ(idx, 1); // White is at index 1
  TEST_END();
}

void test_find_closest_color_red(void) {
  TEST_BEGIN("find_closest_color_red");
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  dither_error_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab red = dither_linear_to_oklab(1.0f, 0.0f, 0.0f);
  int idx = dither_find_closest_color(red, cache.palette_oklab, DITHER_PALETTE_IDEAL_COUNT, 1.0f);
  ASSERT_EQ(idx, 3); // Red is at index 3 in IDEAL palette
  TEST_END();
}

// =================================================================================================
// Test: Cache Initialization
// =================================================================================================

void test_cache_init_ideal(void) {
  TEST_BEGIN("cache_init_ideal");
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  dither_error_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  // Black should have L=0
  ASSERT_NEAR(cache.palette_oklab[0].L, 0.0f, 0.001f);

  // White should have L=1
  ASSERT_NEAR(cache.palette_oklab[1].L, 1.0f, 0.001f);

  // Black should have linear RGB = 0
  ASSERT_NEAR(cache.palette_linear[0].r, 0.0f, 0.001f);

  // White should have linear RGB = 1
  ASSERT_NEAR(cache.palette_linear[1].r, 1.0f, 0.001f);

  TEST_END();
}

void test_cache_init_spectra6_epdopt(void) {
  TEST_BEGIN("cache_init_spectra6_epdopt");
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  dither_error_init_cache(&cache, DITHER_PALETTE_SPECTRA6_EPDOPT,
                          DITHER_PALETTE_SPECTRA6_EPDOPT_COUNT);

  // epdoptimize black is not pure black (25, 30, 33)
  ASSERT_TRUE(cache.palette_oklab[0].L > 0.0f);

  // epdoptimize white is not pure white (232, 232, 232)
  ASSERT_TRUE(cache.palette_oklab[1].L < 1.0f);

  TEST_END();
}

void test_cache_reuses_when_unchanged(void) {
  TEST_BEGIN("cache_reuses_when_unchanged");
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);

  dither_error_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  // Should point to the palette we passed in
  ASSERT_TRUE(cache.last_palette == DITHER_PALETTE_IDEAL);
  ASSERT_EQ(cache.last_palette_count, DITHER_PALETTE_IDEAL_COUNT);

  // Call again with same palette - cache should still point to same palette
  dither_error_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  ASSERT_TRUE(cache.last_palette == DITHER_PALETTE_IDEAL);
  ASSERT_EQ(cache.last_palette_count, DITHER_PALETTE_IDEAL_COUNT);

  TEST_END();
}

// =================================================================================================
// Test: Dither Application (Basic)
// =================================================================================================

void test_dither_solid_black(void) {
  TEST_BEGIN("dither_solid_black");

  // 2x2 solid black image
  float input[16] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f,
                     0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be black (0, 0, 0)
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 0);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
    ASSERT_EQ(output[i * 4 + 3], 255); // Full alpha
  }

  TEST_END();
}

void test_dither_solid_white(void) {
  TEST_BEGIN("dither_solid_white");

  // 2x2 solid white image
  float input[16] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f,
                     1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be white (255, 255, 255)
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 255);
    ASSERT_EQ(output[i * 4 + 1], 255);
    ASSERT_EQ(output[i * 4 + 2], 255);
    ASSERT_EQ(output[i * 4 + 3], 255);
  }

  TEST_END();
}

void test_dither_solid_red(void) {
  TEST_BEGIN("dither_solid_red");

  // 2x2 solid red image (linear red = 1.0)
  float input[16] = {1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                     1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be red (255, 0, 0)
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 255);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
  }

  TEST_END();
}

void test_dither_floyd_steinberg(void) {
  TEST_BEGIN("dither_floyd_steinberg");

  // 2x2 solid black - both algorithms should produce same result
  float input[16] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f,
                     0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_FLOYD_STEINBERG,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be black
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 0);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
  }

  TEST_END();
}

void test_dither_preserves_alpha(void) {
  TEST_BEGIN("dither_preserves_alpha");

  // Image with varying alpha
  float input[16] = {1.0f, 1.0f, 1.0f, 1.0f,  1.0f, 1.0f, 1.0f, 0.5f,
                     1.0f, 1.0f, 1.0f, 0.25f, 1.0f, 1.0f, 1.0f, 0.0f};
  uint8_t output[16] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  ASSERT_EQ(output[3], 255); // 1.0 * 255
  ASSERT_EQ(output[7], 128); // 0.5 * 255 ≈ 128
  ASSERT_EQ(output[11], 64); // 0.25 * 255 ≈ 64
  ASSERT_EQ(output[15], 0);  // 0.0 * 255

  TEST_END();
}

void test_dither_alpha_preserved(void) {
  TEST_BEGIN("dither_alpha_preserved");

  // Image with varying alpha
  float input[8] = {1.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f, 1.0f, 0.5f};
  uint8_t output[8] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 1, &config, &cache);
  ASSERT_EQ(result, 0);

  // Alpha should be preserved from input (0.0 -> 0, 0.5 -> 128)
  ASSERT_EQ(output[3], 0);
  ASSERT_EQ(output[7], 128);

  TEST_END();
}

void test_dither_oklab_error_mode(void) {
  TEST_BEGIN("dither_oklab_error_mode");

  // Solid color should dither the same regardless of error mode
  float input[16] = {1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                     1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 1, // OkLab error diffusion
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);
  int result = dither_error_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // Should still produce red
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 255);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
  }

  TEST_END();
}

void test_dither_width_limit(void) {
  TEST_BEGIN("dither_width_limit");

  // Should reject width > cache capacity
  float input[4] = {1.0f, 1.0f, 1.0f, 1.0f};
  uint8_t output[4] = {99, 99, 99, 99}; // Initialize with non-zero

  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  // Cache only supports width 8
  DITHER_ERROR_CACHE_STATIC(cache, 6, 8);
  // Width exceeds cache capacity - should return error
  int result = dither_error_apply(input, output, 16, 1, &config, &cache);
  ASSERT_EQ(result, -1);

  // Output should be unchanged
  ASSERT_EQ(output[0], 99);

  TEST_END();
}

// =================================================================================================
// Test: Custom Palette
// =================================================================================================

void test_custom_palette(void) {
  TEST_BEGIN("custom_palette");

  // Define a simple 3-color custom palette
  DitherRGB test_palette[] = {
      {0, 0, 0},       // Black
      {128, 128, 128}, // Gray
      {255, 255, 255}  // White
  };

  // Mid-gray input
  float input[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  uint8_t output[4] = {0};

  DitherErrorConfig config = {.palette = test_palette,
                              .palette_count = 3,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 8, 16);
  int result = dither_error_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, 0);

  // Should choose gray (128, 128, 128) as closest to 0.5 linear
  ASSERT_EQ(output[0], 128);
  ASSERT_EQ(output[1], 128);
  ASSERT_EQ(output[2], 128);

  TEST_END();
}

void test_large_palette(void) {
  TEST_BEGIN("large_palette");

  // Create a 16-color grayscale palette
  DitherRGB grayscale[16];
  for (int i = 0; i < 16; i++) {
    uint8_t v = (uint8_t)(i * 17); // 0, 17, 34, ... 255
    grayscale[i] = (DitherRGB){v, v, v};
  }

  // Dark gray input
  float input[4] = {0.1f, 0.1f, 0.1f, 1.0f};
  uint8_t output[4] = {0};

  DitherErrorConfig config = {.palette = grayscale,
                              .palette_count = 16,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f,
                              .oklab_error = 0,
                              .chroma_weight = 1.0f};

  DITHER_ERROR_CACHE_STATIC(cache, 16, 16);
  int result = dither_error_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, 0);

  // Output should be a dark gray (one of the lower palette entries)
  ASSERT_TRUE(output[0] < 100);
  ASSERT_EQ(output[0], output[1]); // Should be grayscale
  ASSERT_EQ(output[1], output[2]);

  TEST_END();
}

// =================================================================================================
// Test: Palette Comparison
// =================================================================================================

void test_palette_spectra6_inky_different(void) {
  TEST_BEGIN("palette_spectra6_inky_different");

  // White in SPECTRA6_INKY palette is grayish
  DITHER_ERROR_CACHE_STATIC(cache1, 6, 16);
  dither_error_init_cache(&cache1, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DITHER_ERROR_CACHE_STATIC(cache2, 6, 16);
  dither_error_init_cache(&cache2, DITHER_PALETTE_SPECTRA6_INKY,
                          DITHER_PALETTE_SPECTRA6_INKY_COUNT);

  // SPECTRA6_INKY white should be darker than IDEAL white
  ASSERT_TRUE(cache2.palette_oklab[1].L < cache1.palette_oklab[1].L);

  TEST_END();
}

// =================================================================================================
// Test: Error Handling
// =================================================================================================

void test_null_input_rejected(void) {
  TEST_BEGIN("null_input_rejected");
  uint8_t output[4] = {0};
  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f};
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);

  int result = dither_error_apply(nullptr, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_null_output_rejected(void) {
  TEST_BEGIN("null_output_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f};
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);

  int result = dither_error_apply(input, nullptr, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_null_palette_rejected(void) {
  TEST_BEGIN("null_palette_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};
  DitherErrorConfig config = {
      .palette = nullptr, .palette_count = 6, .algorithm = DITHER_ATKINSON, .strength = 1.0f};
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);

  int result = dither_error_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_zero_palette_rejected(void) {
  TEST_BEGIN("zero_palette_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};
  DitherErrorConfig config = {.palette = DITHER_PALETTE_IDEAL,
                              .palette_count = 0,
                              .algorithm = DITHER_ATKINSON,
                              .strength = 1.0f};
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);

  int result = dither_error_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_palette_exceeds_cache_rejected(void) {
  TEST_BEGIN("palette_exceeds_cache_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};

  // 16-color palette
  DitherRGB big_palette[16] = {{0}};
  DitherErrorConfig config = {
      .palette = big_palette, .palette_count = 16, .algorithm = DITHER_ATKINSON, .strength = 1.0f};

  // Cache only holds 6 colors
  DITHER_ERROR_CACHE_STATIC(cache, 6, 16);

  int result = dither_error_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

// =================================================================================================
// Test: Ordered Dithering
// =================================================================================================

void test_ordered_solid_black(void) {
  TEST_BEGIN("ordered_solid_black");

  // 2x2 solid black image
  float input[16] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f,
                     0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be black (0, 0, 0) - threshold can't push black to anything else
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 0);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
    ASSERT_EQ(output[i * 4 + 3], 255);
  }

  TEST_END();
}

void test_ordered_solid_white(void) {
  TEST_BEGIN("ordered_solid_white");

  // 2x2 solid white image
  float input[16] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f,
                     1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f};
  uint8_t output[16] = {0};

  // Use spread=0 so threshold doesn't affect result
  // (with high spread, threshold can push white close to other colors in OkLab)
  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.0f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be white (255, 255, 255)
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 255);
    ASSERT_EQ(output[i * 4 + 1], 255);
    ASSERT_EQ(output[i * 4 + 2], 255);
    ASSERT_EQ(output[i * 4 + 3], 255);
  }

  TEST_END();
}

void test_ordered_solid_red(void) {
  TEST_BEGIN("ordered_solid_red");

  // 2x2 solid red image
  float input[16] = {1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                     1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // All pixels should be red (255, 0, 0)
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 255);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
  }

  TEST_END();
}

void test_ordered_bayer_2x2(void) {
  TEST_BEGIN("ordered_bayer_2x2");

  // 2x2 solid black image (black stays black regardless of threshold)
  float input[16] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f,
                     0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_2X2,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // Should produce black output
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 0);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
  }

  TEST_END();
}

void test_ordered_bayer_8x8(void) {
  TEST_BEGIN("ordered_bayer_8x8");

  // 2x2 solid black image
  float input[16] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f,
                     0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_8X8,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // Should produce black output
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 0);
    ASSERT_EQ(output[i * 4 + 1], 0);
    ASSERT_EQ(output[i * 4 + 2], 0);
  }

  TEST_END();
}

void test_ordered_spread_zero(void) {
  TEST_BEGIN("ordered_spread_zero");

  // Mid-gray with black/white palette - spread=0 means no dithering
  DitherRGB bw_palette[] = {{0, 0, 0}, {255, 255, 255}};

  // 2x2 mid-gray image in linear RGB (0.5 linear ≈ 0.74 OkLab L, closer to white)
  float input[16] = {0.5f, 0.5f, 0.5f, 1.0f, 0.5f, 0.5f, 0.5f, 1.0f,
                     0.5f, 0.5f, 0.5f, 1.0f, 0.5f, 0.5f, 0.5f, 1.0f};
  uint8_t output[16] = {0};

  DitherOrderedConfig config = {.palette = bw_palette,
                                .palette_count = 2,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.0f, // No threshold variation
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 2);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  // Linear RGB 0.5 maps to OkLab L ≈ 0.74, which is closer to white (L=1) than black (L=0)
  // All pixels should be white since spread=0 means no threshold variation
  for (int i = 0; i < 4; i++) {
    ASSERT_EQ(output[i * 4 + 0], 255);
    ASSERT_EQ(output[i * 4 + 1], 255);
    ASSERT_EQ(output[i * 4 + 2], 255);
  }

  TEST_END();
}

void test_ordered_spread_creates_pattern(void) {
  TEST_BEGIN("ordered_spread_creates_pattern");

  // Mid-gray with black/white palette and high spread should create pattern
  DitherRGB bw_palette[] = {{0, 0, 0}, {255, 255, 255}};

  // 4x4 mid-gray image
  float input[64];
  for (int i = 0; i < 16; i++) {
    input[i * 4 + 0] = 0.5f;
    input[i * 4 + 1] = 0.5f;
    input[i * 4 + 2] = 0.5f;
    input[i * 4 + 3] = 1.0f;
  }
  uint8_t output[64] = {0};

  DitherOrderedConfig config = {.palette = bw_palette,
                                .palette_count = 2,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 1.0f, // Full threshold variation
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 2);
  int result = dither_ordered_apply(input, output, 4, 4, &config, &cache);
  ASSERT_EQ(result, 0);

  // With spread=1.0 and mid-gray, we should get a mix of black and white
  int black_count = 0;
  int white_count = 0;
  for (int i = 0; i < 16; i++) {
    if (output[i * 4 + 0] == 0)
      black_count++;
    else if (output[i * 4 + 0] == 255)
      white_count++;
  }

  // Should have some of each (not all the same)
  ASSERT_TRUE(black_count > 0);
  ASSERT_TRUE(white_count > 0);

  TEST_END();
}

void test_ordered_preserves_alpha(void) {
  TEST_BEGIN("ordered_preserves_alpha");

  // Image with varying alpha
  float input[16] = {1.0f, 1.0f, 1.0f, 1.0f,  1.0f, 1.0f, 1.0f, 0.5f,
                     1.0f, 1.0f, 1.0f, 0.25f, 1.0f, 1.0f, 1.0f, 0.0f};
  uint8_t output[16] = {0};

  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  ASSERT_EQ(output[3], 255); // 1.0 * 255
  ASSERT_EQ(output[7], 128); // 0.5 * 255 ≈ 128
  ASSERT_EQ(output[11], 64); // 0.25 * 255 ≈ 64
  ASSERT_EQ(output[15], 0);  // 0.0 * 255

  TEST_END();
}

void test_ordered_cache_init(void) {
  TEST_BEGIN("ordered_cache_init");

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  ASSERT_EQ(result, 0);

  // Black should have L=0
  ASSERT_NEAR(cache.palette_oklab[0].L, 0.0f, 0.001f);

  // White should have L=1
  ASSERT_NEAR(cache.palette_oklab[1].L, 1.0f, 0.001f);

  // Cache should track the palette
  ASSERT_TRUE(cache.last_palette == DITHER_PALETTE_IDEAL);
  ASSERT_EQ(cache.last_palette_count, DITHER_PALETTE_IDEAL_COUNT);

  TEST_END();
}

void test_ordered_cache_reuses(void) {
  TEST_BEGIN("ordered_cache_reuses");

  DITHER_ORDERED_CACHE_STATIC(cache, 6);

  dither_ordered_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  ASSERT_TRUE(cache.last_palette == DITHER_PALETTE_IDEAL);

  // Call again - should still point to same palette
  dither_ordered_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  ASSERT_TRUE(cache.last_palette == DITHER_PALETTE_IDEAL);

  TEST_END();
}

void test_ordered_null_input_rejected(void) {
  TEST_BEGIN("ordered_null_input_rejected");

  uint8_t output[4] = {0};
  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(nullptr, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);

  TEST_END();
}

void test_ordered_null_output_rejected(void) {
  TEST_BEGIN("ordered_null_output_rejected");

  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  DitherOrderedConfig config = {.palette = DITHER_PALETTE_IDEAL,
                                .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, nullptr, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);

  TEST_END();
}

void test_ordered_palette_exceeds_cache(void) {
  TEST_BEGIN("ordered_palette_exceeds_cache");

  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};

  DitherRGB big_palette[16] = {{0}};
  DitherOrderedConfig config = {.palette = big_palette,
                                .palette_count = 16,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.5f,
                                .chroma_weight = 1.0f};

  // Cache only holds 6 colors
  DITHER_ORDERED_CACHE_STATIC(cache, 6);
  int result = dither_ordered_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);

  TEST_END();
}

void test_ordered_chroma_weight_low_prefers_lightness(void) {
  TEST_BEGIN("ordered_chroma_weight_low_prefers_lightness");

  // Input: pure red (1.0, 0.0, 0.0) linear RGB → OkLab L≈0.63, a≈0.23, b≈0.13
  // Palette designed so chroma_weight flips the winner:
  // - Dark red (80,0,0): L≈0.32 (far), but similar hue (close in a,b)
  // - Mid gray (160,160,160): L≈0.64 (close), but no chroma (far in a,b)
  DitherRGB palette[] = {
      {80, 0, 0},     // Dark red: L≈0.32, similar hue
      {160, 160, 160} // Mid gray: L≈0.64, no chroma
  };

  float input[4] = {1.0f, 0.0f, 0.0f, 1.0f}; // Pure red
  uint8_t output[4] = {0};

  // With low chroma_weight (clamped to 0.5), lightness dominates:
  // dist_gray = 4*dL² + 0.5*chroma² ≈ 4*0.0001 + 0.5*0.07 ≈ 0.035
  // dist_red  = 4*dL² + 0.5*chroma² ≈ 4*0.096 + 0.5*0.012 ≈ 0.39
  // Gray wins (much lower distance)
  DitherOrderedConfig config = {.palette = palette,
                                .palette_count = 2,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.0f,
                                .chroma_weight = 0.5f};

  DITHER_ORDERED_CACHE_STATIC(cache, 2);
  int result = dither_ordered_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, 0);

  // Should pick gray (closer in lightness)
  ASSERT_EQ(output[0], 160);
  ASSERT_EQ(output[1], 160);
  ASSERT_EQ(output[2], 160);

  TEST_END();
}

void test_ordered_chroma_weight_high_prefers_hue(void) {
  TEST_BEGIN("ordered_chroma_weight_high_prefers_hue");

  // Same palette and input as above
  DitherRGB palette[] = {
      {80, 0, 0},     // Dark red: L≈0.32, similar hue
      {160, 160, 160} // Mid gray: L≈0.64, no chroma
  };

  float input[4] = {1.0f, 0.0f, 0.0f, 1.0f}; // Pure red
  uint8_t output[4] = {0};

  // With high chroma_weight (4.0), chroma/hue dominates:
  // dist_gray = 0.5*dL² + 4*chroma² ≈ 0.5*0.0001 + 4*0.07 ≈ 0.28
  // dist_red  = 0.5*dL² + 4*chroma² ≈ 0.5*0.096 + 4*0.012 ≈ 0.096
  // Red wins (lower distance)
  DitherOrderedConfig config = {.palette = palette,
                                .palette_count = 2,
                                .matrix = DITHER_BAYER_4X4,
                                .spread = 0.0f,
                                .chroma_weight = 4.0f};

  DITHER_ORDERED_CACHE_STATIC(cache, 2);
  int result = dither_ordered_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, 0);

  // Should pick dark red (closer in hue/chroma)
  ASSERT_EQ(output[0], 80);
  ASSERT_EQ(output[1], 0);
  ASSERT_EQ(output[2], 0);

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Dither quantizer tests\n");
  printf("===================\n");

  // sRGB to linear tests
  test_srgb_to_linear_black();
  test_srgb_to_linear_white();
  test_srgb_to_linear_mid_gray();

  // OkLab conversion tests
  test_linear_to_oklab_black();
  test_linear_to_oklab_white();
  test_linear_to_oklab_red();
  test_linear_to_oklab_green();
  test_linear_to_oklab_blue();

  // OkLab chroma tests
  test_oklab_chroma_grayscale();
  test_oklab_chroma_saturated();

  // OkLab distance tests
  test_oklab_distance_same_color();
  test_oklab_distance_different_lightness();
  test_oklab_distance_chroma_weight();

  // Palette color finding tests
  test_find_closest_color_black();
  test_find_closest_color_white();
  test_find_closest_color_red();

  // Cache tests
  test_cache_init_ideal();
  test_cache_init_spectra6_epdopt();
  test_cache_reuses_when_unchanged();

  // Dither application tests
  test_dither_solid_black();
  test_dither_solid_white();
  test_dither_solid_red();
  test_dither_floyd_steinberg();
  test_dither_preserves_alpha();
  test_dither_alpha_preserved();
  test_dither_oklab_error_mode();
  test_dither_width_limit();

  // Custom palette tests
  test_custom_palette();
  test_large_palette();

  // Palette comparison tests
  test_palette_spectra6_inky_different();

  // Error handling tests
  test_null_input_rejected();
  test_null_output_rejected();
  test_null_palette_rejected();
  test_zero_palette_rejected();
  test_palette_exceeds_cache_rejected();

  // Ordered dithering tests
  test_ordered_solid_black();
  test_ordered_solid_white();
  test_ordered_solid_red();
  test_ordered_bayer_2x2();
  test_ordered_bayer_8x8();
  test_ordered_spread_zero();
  test_ordered_spread_creates_pattern();
  test_ordered_preserves_alpha();
  test_ordered_cache_init();
  test_ordered_cache_reuses();
  test_ordered_null_input_rejected();
  test_ordered_null_output_rejected();
  test_ordered_palette_exceeds_cache();
  test_ordered_chroma_weight_low_prefers_lightness();
  test_ordered_chroma_weight_high_prefers_hue();

  TEST_RUNNER_END();
}
