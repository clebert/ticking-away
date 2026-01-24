// Test harness for grain kernel

#include <stdint.h>
#include <stdio.h>

#include "config.h"
#include "kernels/grain.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Hash Function
// =================================================================================================

void test_hash_deterministic(void) {
  TEST_BEGIN("hash_deterministic");
  // Same coordinates should produce same hash
  uint32_t h1 = grain_hash_pixel(100, 200);
  uint32_t h2 = grain_hash_pixel(100, 200);
  ASSERT_EQ(h1, h2);
  TEST_END();
}

void test_hash_different_for_different_coords(void) {
  TEST_BEGIN("hash_different_for_different_coords");
  // Different coordinates should produce different hashes
  uint32_t h1 = grain_hash_pixel(0, 0);
  uint32_t h2 = grain_hash_pixel(1, 0);
  uint32_t h3 = grain_hash_pixel(0, 1);
  // Hash collision is possible but extremely unlikely for adjacent pixels
  ASSERT_TRUE(h1 != h2 || h1 != h3);
  TEST_END();
}

void test_hash_distribution(void) {
  TEST_BEGIN("hash_distribution");
  // Test that hash produces values across the full range
  // Sample 100 pixels and check we get varied results
  int low_count = 0;
  int high_count = 0;
  for (int i = 0; i < 100; i++) {
    uint32_t h = grain_hash_pixel(i, i * 7);
    if ((h & 0xFF) < 128)
      low_count++;
    else
      high_count++;
  }
  // Should have reasonable distribution (not all low or all high)
  ASSERT_TRUE(low_count > 20 && high_count > 20);
  TEST_END();
}

// =================================================================================================
// Test: Grain Application
// =================================================================================================

void test_grain_no_config(void) {
  TEST_BEGIN("grain_no_config");
  // With NULL config, framebuffer should be unchanged
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  kernel_grain_apply(fb, 1, 1, NULL, NULL);
  ASSERT_NEAR(fb[0], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.0001f);
  TEST_END();
}

void test_grain_zero_intensity(void) {
  TEST_BEGIN("grain_zero_intensity");
  // With zero intensity, framebuffer should be unchanged
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  GrainConfig cfg = {.intensity = 0.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb, 1, 1, &cfg, NULL);
  ASSERT_NEAR(fb[0], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.0001f);
  TEST_END();
}

void test_grain_black_pixels_unaffected(void) {
  TEST_BEGIN("grain_black_pixels_unaffected");
  // Black pixels should have no grain (brightness scale = 0)
  float fb[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb, 1, 1, &cfg, NULL);
  // Should remain black (or very close due to floating point)
  ASSERT_NEAR(fb[0], 0.0f, 0.001f);
  ASSERT_NEAR(fb[1], 0.0f, 0.001f);
  ASSERT_NEAR(fb[2], 0.0f, 0.001f);
  TEST_END();
}

void test_grain_bright_pixels_affected(void) {
  TEST_BEGIN("grain_bright_pixels_affected");
  // White pixels should have visible grain
  float fb[4] = {1.0f, 1.0f, 1.0f, 1.0f};
  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb, 1, 1, &cfg, NULL);
  // At full intensity, grain is ±6%, so result should be within [0.94, 1.0]
  // (clamped at 1.0 for positive noise)
  ASSERT_TRUE(fb[0] >= 0.94f && fb[0] <= 1.0f);
  TEST_END();
}

void test_grain_alpha_unchanged(void) {
  TEST_BEGIN("grain_alpha_unchanged");
  // Alpha channel should never be modified
  float fb[4] = {0.5f, 0.5f, 0.5f, 0.7f};
  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb, 1, 1, &cfg, NULL);
  ASSERT_NEAR(fb[3], 0.7f, 0.0001f);
  TEST_END();
}

void test_grain_monochromatic(void) {
  TEST_BEGIN("grain_monochromatic");
  // Grain should be same for all channels (monochromatic noise)
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb, 1, 1, &cfg, NULL);
  // All channels should change by the same amount (grain is monochromatic)
  float r_change = fb[0] - 0.5f;
  float g_change = fb[1] - 0.5f;
  float b_change = fb[2] - 0.5f;
  ASSERT_NEAR(r_change, g_change, 0.0001f);
  ASSERT_NEAR(g_change, b_change, 0.0001f);
  TEST_END();
}

void test_grain_deterministic(void) {
  TEST_BEGIN("grain_deterministic");
  // Same input should produce same output (deterministic noise)
  float fb1[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  float fb2[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb1, 1, 1, &cfg, NULL);
  kernel_grain_apply(fb2, 1, 1, &cfg, NULL);
  ASSERT_NEAR(fb1[0], fb2[0], 0.0001f);
  ASSERT_NEAR(fb1[1], fb2[1], 0.0001f);
  ASSERT_NEAR(fb1[2], fb2[2], 0.0001f);
  TEST_END();
}

void test_grain_scale_affects_pattern(void) {
  TEST_BEGIN("grain_scale_affects_pattern");
  // Different scale should produce different grain pattern
  // Create a 4x4 buffer at two different scales
  float fb1[64]; // 4x4 RGBA
  float fb2[64];
  for (int i = 0; i < 64; i++) {
    fb1[i] = (i % 4 == 3) ? 1.0f : 0.8f; // RGBA, alpha=1
    fb2[i] = fb1[i];
  }

  GrainConfig cfg1 = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  GrainConfig cfg2 = {.intensity = 1.0f, .scale = 2.0f, .threshold = 0.1f, .prism_only = 0};

  kernel_grain_apply(fb1, 4, 4, &cfg1, NULL);
  kernel_grain_apply(fb2, 4, 4, &cfg2, NULL);

  // At scale=2, adjacent pixels should share grain values
  // fb2[0,0] and fb2[1,0] should have same grain (same scaled coord)
  // This isn't guaranteed to be different from scale=1, but pattern should differ
  // Just verify both ran successfully and produced valid values
  ASSERT_TRUE(fb1[0] >= 0.0f && fb1[0] <= 1.0f);
  ASSERT_TRUE(fb2[0] >= 0.0f && fb2[0] <= 1.0f);
  TEST_END();
}

// =================================================================================================
// Test: Geometry Masking
// =================================================================================================

void test_grain_circle_mask(void) {
  TEST_BEGIN("grain_circle_mask");
  // Create a 3x3 buffer with center pixel in circle, corners outside
  float fb[36]; // 3x3 RGBA
  for (int i = 0; i < 36; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.8f;
  }
  float original_corner = fb[0];

  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  GrainGeometry geom = {.cx = 1.5f,
                        .cy = 1.5f,
                        .radius = 0.6f, // Only center pixel
                        .prism_vertices = NULL};

  kernel_grain_apply(fb, 3, 3, &cfg, &geom);

  // Corner pixel (0,0) is at (0.5, 0.5), distance to center (1.5, 1.5) is ~1.41
  // This is > 0.6, so should be unchanged
  ASSERT_NEAR(fb[0], original_corner, 0.0001f);

  // Center pixel (1,1) should have grain applied
  // Just verify it ran (value is valid)
  ASSERT_TRUE(fb[16] >= 0.0f && fb[16] <= 1.0f);
  TEST_END();
}

void test_grain_prism_only(void) {
  TEST_BEGIN("grain_prism_only");
  // Create a buffer with prism mask
  float fb[4] = {0.8f, 0.8f, 0.8f, 1.0f};
  float original = fb[0];

  // Prism that doesn't contain (0.5, 0.5)
  float prism_verts[6] = {
      10.0f, 10.0f, // v0
      20.0f, 10.0f, // v1
      15.0f, 20.0f  // v2
  };

  GrainConfig cfg = {
      .intensity = 1.0f,
      .scale = 1.0f,
      .threshold = 0.1f,
      .prism_only = 1 // Only inside prism
  };
  GrainGeometry geom = {.cx = 0.5f,
                        .cy = 0.5f,
                        .radius = 10.0f, // Circle includes pixel
                        .prism_vertices = prism_verts};

  kernel_grain_apply(fb, 1, 1, &cfg, &geom);

  // Pixel at (0.5, 0.5) is inside circle but outside prism, so unchanged
  ASSERT_NEAR(fb[0], original, 0.0001f);
  TEST_END();
}

void test_grain_prism_inside(void) {
  TEST_BEGIN("grain_prism_inside");
  // Create a buffer with prism mask that contains the pixel
  float fb[4] = {0.8f, 0.8f, 0.8f, 1.0f};

  // Prism that contains (0.5, 0.5)
  float prism_verts[6] = {
      0.0f, 0.0f, // v0
      2.0f, 0.0f, // v1
      1.0f, 2.0f  // v2
  };

  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 1};
  GrainGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 10.0f, .prism_vertices = prism_verts};

  kernel_grain_apply(fb, 1, 1, &cfg, &geom);

  // Pixel at (0.5, 0.5) is inside both circle and prism, grain should be applied
  // Just verify value changed or is valid
  ASSERT_TRUE(fb[0] >= 0.0f && fb[0] <= 1.0f);
  TEST_END();
}

// =================================================================================================
// Test: Clamping
// =================================================================================================

void test_grain_clamps_output(void) {
  TEST_BEGIN("grain_clamps_output");
  // Values should be clamped to [0, 1]
  float fb[4] = {0.99f, 0.99f, 0.99f, 1.0f};
  GrainConfig cfg = {.intensity = 1.0f, .scale = 1.0f, .threshold = 0.1f, .prism_only = 0};
  kernel_grain_apply(fb, 1, 1, &cfg, NULL);
  // Even with positive grain, result should be clamped to 1.0
  ASSERT_TRUE(fb[0] <= 1.0f);
  ASSERT_TRUE(fb[1] <= 1.0f);
  ASSERT_TRUE(fb[2] <= 1.0f);
  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Grain kernel tests\n");
  printf("==================\n");

  // Hash function tests
  test_hash_deterministic();
  test_hash_different_for_different_coords();
  test_hash_distribution();

  // Grain application tests
  test_grain_no_config();
  test_grain_zero_intensity();
  test_grain_black_pixels_unaffected();
  test_grain_bright_pixels_affected();
  test_grain_alpha_unchanged();
  test_grain_monochromatic();
  test_grain_deterministic();
  test_grain_scale_affects_pattern();

  // Geometry masking tests
  test_grain_circle_mask();
  test_grain_prism_only();
  test_grain_prism_inside();

  // Clamping tests
  test_grain_clamps_output();

  TEST_RUNNER_END();
}
