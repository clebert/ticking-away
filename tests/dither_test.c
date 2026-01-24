// Test harness for dither kernel

#include "kernels/dither.h"
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
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab black = dither_linear_to_oklab(0.0f, 0.0f, 0.0f);
  int idx = dither_find_closest_color(black, cache.palette_oklab, DITHER_PALETTE_IDEAL_COUNT, 1.0f);
  ASSERT_EQ(idx, 0); // Black is at index 0
  TEST_END();
}

void test_find_closest_color_white(void) {
  TEST_BEGIN("find_closest_color_white");
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab white = dither_linear_to_oklab(1.0f, 1.0f, 1.0f);
  int idx = dither_find_closest_color(white, cache.palette_oklab, DITHER_PALETTE_IDEAL_COUNT, 1.0f);
  ASSERT_EQ(idx, 1); // White is at index 1
  TEST_END();
}

void test_find_closest_color_red(void) {
  TEST_BEGIN("find_closest_color_red");
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab red = dither_linear_to_oklab(1.0f, 0.0f, 0.0f);
  int idx = dither_find_closest_color(red, cache.palette_oklab, DITHER_PALETTE_IDEAL_COUNT, 1.0f);
  ASSERT_EQ(idx, 3); // Red is at index 3 in IDEAL palette
  TEST_END();
}

void test_find_closest_bw_dark(void) {
  TEST_BEGIN("find_closest_bw_dark");
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab dark = dither_linear_to_oklab(0.1f, 0.1f, 0.1f);
  int idx = dither_find_closest_bw(dark, cache.palette_oklab, 0, 1, 1.0f);
  ASSERT_EQ(idx, 0); // Should choose black (index 0)
  TEST_END();
}

void test_find_closest_bw_light(void) {
  TEST_BEGIN("find_closest_bw_light");
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DitherOkLab light = dither_linear_to_oklab(0.9f, 0.9f, 0.9f);
  int idx = dither_find_closest_bw(light, cache.palette_oklab, 0, 1, 1.0f);
  ASSERT_EQ(idx, 1); // Should choose white (index 1)
  TEST_END();
}

// =================================================================================================
// Test: Cache Initialization
// =================================================================================================

void test_cache_init_ideal(void) {
  TEST_BEGIN("cache_init_ideal");
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

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

void test_cache_init_spectra6(void) {
  TEST_BEGIN("cache_init_spectra6");
  DITHER_CACHE_STATIC(cache, 6, 16);
  kernel_dither_init_cache(&cache, DITHER_PALETTE_SPECTRA6, DITHER_PALETTE_SPECTRA6_COUNT);

  // Spectra6 black is not pure black (25, 30, 33)
  ASSERT_TRUE(cache.palette_oklab[0].L > 0.0f);

  // Spectra6 white is not pure white (232, 232, 232)
  ASSERT_TRUE(cache.palette_oklab[1].L < 1.0f);

  TEST_END();
}

void test_cache_reuses_when_unchanged(void) {
  TEST_BEGIN("cache_reuses_when_unchanged");
  DITHER_CACHE_STATIC(cache, 6, 16);

  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  const DitherRGB *first_palette = cache.last_palette;

  kernel_dither_init_cache(&cache, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);
  const DitherRGB *second_palette = cache.last_palette;

  // Should be the same pointer (cache reused)
  ASSERT_TRUE(first_palette == second_palette);

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

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 2, &config, &cache);
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

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 2, &config, &cache);
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

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 2, &config, &cache);
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

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_FLOYD_STEINBERG,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 2, &config, &cache);
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

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 2, &config, &cache);
  ASSERT_EQ(result, 0);

  ASSERT_EQ(output[3], 255); // 1.0 * 255
  ASSERT_EQ(output[7], 128); // 0.5 * 255 ≈ 128
  ASSERT_EQ(output[11], 64); // 0.25 * 255 ≈ 64
  ASSERT_EQ(output[15], 0);  // 0.0 * 255

  TEST_END();
}

void test_dither_opaque_mode(void) {
  TEST_BEGIN("dither_opaque_mode");

  // Image with varying alpha
  float input[8] = {1.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f, 1.0f, 0.5f};
  uint8_t output[8] = {0};

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 0, // Don't preserve alpha
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 1, &config, &cache);
  ASSERT_EQ(result, 0);

  // Both should be fully opaque
  ASSERT_EQ(output[3], 255);
  ASSERT_EQ(output[7], 255);

  TEST_END();
}

void test_dither_oklab_error_mode(void) {
  TEST_BEGIN("dither_oklab_error_mode");

  // Solid color should dither the same regardless of error mode
  float input[16] = {1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f,
                     1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[16] = {0};

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 1, // OkLab error diffusion
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 6, 16);
  int result = kernel_dither_apply(input, output, 2, 2, &config, &cache);
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

  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .bw_black_idx = 0,
                         .bw_white_idx = 1,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  // Cache only supports width 8
  DITHER_CACHE_STATIC(cache, 6, 8);
  // Width exceeds cache capacity - should return error
  int result = kernel_dither_apply(input, output, 16, 1, &config, &cache);
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

  DitherConfig config = {.palette = test_palette,
                         .palette_count = 3,
                         .bw_black_idx = 0,
                         .bw_white_idx = 2,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 8, 16);
  int result = kernel_dither_apply(input, output, 1, 1, &config, &cache);
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

  DitherConfig config = {.palette = grayscale,
                         .palette_count = 16,
                         .bw_black_idx = 0,
                         .bw_white_idx = 15,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f,
                         .oklab_error = 0,
                         .preserve_alpha = 1,
                         .bw_threshold = 0.0f,
                         .chroma_weight = 1.0f};

  DITHER_CACHE_STATIC(cache, 16, 16);
  int result = kernel_dither_apply(input, output, 1, 1, &config, &cache);
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

void test_palette_device_different(void) {
  TEST_BEGIN("palette_device_different");

  // White in DEVICE palette is grayish
  DITHER_CACHE_STATIC(cache1, 6, 16);
  kernel_dither_init_cache(&cache1, DITHER_PALETTE_IDEAL, DITHER_PALETTE_IDEAL_COUNT);

  DITHER_CACHE_STATIC(cache2, 6, 16);
  kernel_dither_init_cache(&cache2, DITHER_PALETTE_DEVICE, DITHER_PALETTE_DEVICE_COUNT);

  // DEVICE white should be darker than IDEAL white
  ASSERT_TRUE(cache2.palette_oklab[1].L < cache1.palette_oklab[1].L);

  TEST_END();
}

// =================================================================================================
// Test: Error Handling
// =================================================================================================

void test_null_input_rejected(void) {
  TEST_BEGIN("null_input_rejected");
  uint8_t output[4] = {0};
  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f};
  DITHER_CACHE_STATIC(cache, 6, 16);

  int result = kernel_dither_apply(nullptr, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_null_output_rejected(void) {
  TEST_BEGIN("null_output_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = DITHER_PALETTE_IDEAL_COUNT,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f};
  DITHER_CACHE_STATIC(cache, 6, 16);

  int result = kernel_dither_apply(input, nullptr, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_null_palette_rejected(void) {
  TEST_BEGIN("null_palette_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};
  DitherConfig config = {
      .palette = nullptr, .palette_count = 6, .algorithm = DITHER_ATKINSON, .strength = 1.0f};
  DITHER_CACHE_STATIC(cache, 6, 16);

  int result = kernel_dither_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_zero_palette_rejected(void) {
  TEST_BEGIN("zero_palette_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};
  DitherConfig config = {.palette = DITHER_PALETTE_IDEAL,
                         .palette_count = 0,
                         .algorithm = DITHER_ATKINSON,
                         .strength = 1.0f};
  DITHER_CACHE_STATIC(cache, 6, 16);

  int result = kernel_dither_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

void test_palette_exceeds_cache_rejected(void) {
  TEST_BEGIN("palette_exceeds_cache_rejected");
  float input[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  uint8_t output[4] = {0};

  // 16-color palette
  DitherRGB big_palette[16] = {{0}};
  DitherConfig config = {
      .palette = big_palette, .palette_count = 16, .algorithm = DITHER_ATKINSON, .strength = 1.0f};

  // Cache only holds 6 colors
  DITHER_CACHE_STATIC(cache, 6, 16);

  int result = kernel_dither_apply(input, output, 1, 1, &config, &cache);
  ASSERT_EQ(result, -1);
  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Dither kernel tests\n");
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
  test_find_closest_bw_dark();
  test_find_closest_bw_light();

  // Cache tests
  test_cache_init_ideal();
  test_cache_init_spectra6();
  test_cache_reuses_when_unchanged();

  // Dither application tests
  test_dither_solid_black();
  test_dither_solid_white();
  test_dither_solid_red();
  test_dither_floyd_steinberg();
  test_dither_preserves_alpha();
  test_dither_opaque_mode();
  test_dither_oklab_error_mode();
  test_dither_width_limit();

  // Custom palette tests
  test_custom_palette();
  test_large_palette();

  // Palette comparison tests
  test_palette_device_different();

  // Error handling tests
  test_null_input_rejected();
  test_null_output_rejected();
  test_null_palette_rejected();
  test_zero_palette_rejected();
  test_palette_exceeds_cache_rejected();

  TEST_RUNNER_END();
}
