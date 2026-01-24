// =================================================================================================
// Gradient Layer Tests
// =================================================================================================
// Tests for gradient color interpolation and palette management.

#include <stdio.h>

#include "geometry/prism.h"
#include "geometry/types.h"
#include "layers/gradient.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Palette Cache Tests
// =================================================================================================

void test_palette_cache_init(void) {
  TEST_BEGIN("palette_cache_init");
  GradientPaletteCache cache;
  cache.initialized = 0;
  cache.palette = -1;

  gradient_init_palette_cache(&cache, 0);

  ASSERT_TRUE(cache.initialized);
  ASSERT_EQ(cache.palette, 0);

  // First band should be red (high R, low G, low B)
  ASSERT_TRUE(cache.linear[0].r > 0.5f);
  ASSERT_TRUE(cache.linear[0].g < 0.3f);
  ASSERT_TRUE(cache.linear[0].b < 0.3f);

  // Last band should be violet (some R, low G, high B)
  ASSERT_TRUE(cache.linear[6].b > 0.5f);
  TEST_END();
}

void test_palette_cache_reinit_same(void) {
  TEST_BEGIN("palette_cache_reinit_same");
  GradientPaletteCache cache;
  cache.initialized = 0;
  cache.palette = -1;

  gradient_init_palette_cache(&cache, 0);
  float original_r = cache.linear[0].r;

  // Re-init with same palette should be no-op
  gradient_init_palette_cache(&cache, 0);
  ASSERT_NEAR(cache.linear[0].r, original_r, 0.001f);
  TEST_END();
}

void test_palette_cache_reinit_different(void) {
  TEST_BEGIN("palette_cache_reinit_different");
  GradientPaletteCache cache;
  cache.initialized = 0;
  cache.palette = -1;

  gradient_init_palette_cache(&cache, 0);

  // Re-init with different palette should change values
  gradient_init_palette_cache(&cache, 1); // SATURATED
  ASSERT_EQ(cache.palette, 1);
  // SATURATED has pure red (255,0,0) vs BALANCED (255,64,64)
  ASSERT_TRUE(cache.linear[0].g < 0.01f);
  TEST_END();
}

void test_palette_cache_bounds(void) {
  TEST_BEGIN("palette_cache_bounds");
  GradientPaletteCache cache;
  cache.initialized = 0;
  cache.palette = -1;

  // Negative palette should clamp to 0
  gradient_init_palette_cache(&cache, -5);
  ASSERT_EQ(cache.palette, 0);

  // Very large palette should clamp to 0
  cache.initialized = 0;
  gradient_init_palette_cache(&cache, 100);
  ASSERT_EQ(cache.palette, 0);
  TEST_END();
}

void test_palette_cache_static_macro(void) {
  TEST_BEGIN("palette_cache_static_macro");
  GRADIENT_PALETTE_CACHE_STATIC(cache);

  ASSERT_EQ(cache.palette, -1);
  ASSERT_EQ(cache.initialized, 0);

  gradient_init_palette_cache(&cache, 2);
  ASSERT_TRUE(cache.initialized);
  TEST_END();
}

// =================================================================================================
// Color Interpolation Tests
// =================================================================================================

void test_interpolate_at_red(void) {
  TEST_BEGIN("interpolate_at_red");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  GradientRGBLinear color = gradient_interpolate_color(&cache, 0.0f);

  // At t=0, should be red
  ASSERT_TRUE(color.r > 0.5f);
  ASSERT_TRUE(color.g < 0.3f);
  ASSERT_TRUE(color.b < 0.3f);
  TEST_END();
}

void test_interpolate_at_violet(void) {
  TEST_BEGIN("interpolate_at_violet");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  GradientRGBLinear color = gradient_interpolate_color(&cache, 1.0f);

  // At t=1, should be violet (high B, some R)
  ASSERT_TRUE(color.b > 0.5f);
  TEST_END();
}

void test_interpolate_midpoint(void) {
  TEST_BEGIN("interpolate_midpoint");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  GradientRGBLinear color = gradient_interpolate_color(&cache, 0.5f);

  // At t=0.5, should be in green/cyan region
  // The exact values depend on OkLab interpolation
  ASSERT_TRUE(color.g > 0.3f);
  TEST_END();
}

void test_interpolate_infrared(void) {
  TEST_BEGIN("interpolate_infrared");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  GradientRGBLinear color = gradient_interpolate_color(&cache, -0.5f);

  // Infrared should be darker red
  ASSERT_TRUE(color.r > 0.1f);
  ASSERT_TRUE(color.g < 0.1f);
  ASSERT_TRUE(color.b < 0.1f);
  TEST_END();
}

void test_interpolate_ultraviolet(void) {
  TEST_BEGIN("interpolate_ultraviolet");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  GradientRGBLinear color = gradient_interpolate_color(&cache, 1.5f);

  // Ultraviolet should be deeper purple
  ASSERT_TRUE(color.b > 0.1f);
  TEST_END();
}

void test_interpolate_extreme_extrapolation(void) {
  TEST_BEGIN("interpolate_extreme_extrapolation");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  // Very negative t
  GradientRGBLinear color_ir = gradient_interpolate_color(&cache, -5.0f);
  ASSERT_TRUE(color_ir.r >= 0.0f);

  // Very positive t
  GradientRGBLinear color_uv = gradient_interpolate_color(&cache, 5.0f);
  ASSERT_TRUE(color_uv.b >= 0.0f);
  TEST_END();
}

void test_interpolate_between_bands(void) {
  TEST_BEGIN("interpolate_between_bands");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  // t values between bands should produce interpolated colors
  // t = 1/6 should be between red and orange
  GradientRGBLinear c1 = gradient_interpolate_color(&cache, 1.0f / 6.0f);

  // Red channel should be significant
  ASSERT_TRUE(c1.r > 0.3f);
  TEST_END();
}

// =================================================================================================
// OkLab Consistency Tests
// =================================================================================================

void test_oklab_colors_computed(void) {
  TEST_BEGIN("oklab_colors_computed");
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  // OkLab L should be in reasonable range (0-1 typically)
  for (int i = 0; i < GRADIENT_NUM_BANDS; i++) {
    ASSERT_TRUE(cache.oklab[i].L > 0.0f);
    ASSERT_TRUE(cache.oklab[i].L < 1.5f);
  }
  TEST_END();
}

// =================================================================================================
// Gradient Draw Tests (basic validation)
// =================================================================================================

void test_gradient_draw_no_crash(void) {
  TEST_BEGIN("gradient_draw_no_crash");
  // Create a small framebuffer
  float fb[16 * 16 * 4];
  for (int i = 0; i < 16 * 16 * 4; i++)
    fb[i] = 0.0f;

  // Create a prism
  Prism prism;
  prism_create(8.0f, 8.0f, 6.0f, 60.0f, &prism);

  // Initialize palette
  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  // Draw gradient - should not crash
  gradient_draw_continuous(fb, 16, 16, GRADIENT_MODE_EXTERNAL, 8.0f, 8.0f, // origin
                           8.0f, 8.0f, 6.0f,                               // circle
                           0.0f, 1.0f,                                     // angles
                           &prism, 1.0f, 0, &cache);

  // Verify no NaN in output
  int has_nan = 0;
  for (int i = 0; i < 16 * 16 * 4; i++) {
    if (fb[i] != fb[i])
      has_nan = 1; // NaN check
  }
  ASSERT_FALSE(has_nan);
  TEST_END();
}

void test_gradient_draw_internal_mode(void) {
  TEST_BEGIN("gradient_draw_internal_mode");
  float fb[16 * 16 * 4];
  for (int i = 0; i < 16 * 16 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(8.0f, 8.0f, 6.0f, 60.0f, &prism);

  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  // Draw internal gradient - use wider angle sweep to cover prism
  // Prism spans roughly from 0.5 to 2.5 radians when measured from center
  gradient_draw_continuous(fb, 16, 16, GRADIENT_MODE_INTERNAL, 8.0f, 8.0f, // origin
                           0, 0, 0,    // cx, cy, radius unused for internal
                           0.5f, 2.5f, // angles (wider sweep)
                           &prism, 1.0f, 0, &cache);

  // Should have written some pixels inside prism
  int nonzero_count = 0;
  for (int i = 0; i < 16 * 16 * 4; i += 4) {
    if (fb[i] > 0.0f || fb[i + 1] > 0.0f || fb[i + 2] > 0.0f) {
      nonzero_count++;
    }
  }
  ASSERT_TRUE(nonzero_count > 0);
  TEST_END();
}

void test_gradient_reverse_spectrum(void) {
  TEST_BEGIN("gradient_reverse_spectrum");
  float fb1[16 * 16 * 4];
  float fb2[16 * 16 * 4];
  for (int i = 0; i < 16 * 16 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  Prism prism;
  prism_create(8.0f, 8.0f, 6.0f, 60.0f, &prism);

  GRADIENT_PALETTE_CACHE_STATIC(cache);
  gradient_init_palette_cache(&cache, 0);

  // Draw normal - use angles that cover prism
  gradient_draw_continuous(fb1, 16, 16, GRADIENT_MODE_INTERNAL, 8.0f, 8.0f, 0, 0, 0, 0.5f, 2.5f,
                           &prism, 1.0f, 0, &cache);

  // Draw reversed
  gradient_draw_continuous(fb2, 16, 16, GRADIENT_MODE_INTERNAL, 8.0f, 8.0f, 0, 0, 0, 0.5f, 2.5f,
                           &prism, 1.0f, 1, &cache);

  // The two should be different (reversed colors)
  int diff_count = 0;
  for (int i = 0; i < 16 * 16 * 4; i++) {
    if (fb1[i] != fb2[i])
      diff_count++;
  }
  ASSERT_TRUE(diff_count > 0);
  TEST_END();
}

// =================================================================================================
// Test Runner
// =================================================================================================

int main(void) {
  printf("Gradient Layer Tests\n");
  printf("====================\n\n");

  // Palette cache tests
  test_palette_cache_init();
  test_palette_cache_reinit_same();
  test_palette_cache_reinit_different();
  test_palette_cache_bounds();
  test_palette_cache_static_macro();

  // Color interpolation tests
  test_interpolate_at_red();
  test_interpolate_at_violet();
  test_interpolate_midpoint();
  test_interpolate_infrared();
  test_interpolate_ultraviolet();
  test_interpolate_extreme_extrapolation();
  test_interpolate_between_bands();

  // OkLab tests
  test_oklab_colors_computed();

  // Gradient draw tests
  test_gradient_draw_no_crash();
  test_gradient_draw_internal_mode();
  test_gradient_reverse_spectrum();

  TEST_RUNNER_END();
}
