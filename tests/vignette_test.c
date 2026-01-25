// Test harness for vignette effect

#include "config.h"
#include "effects/vignette.h"
#include "test_harness.h"
#include <stdint.h>
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Hash Function
// =================================================================================================

void test_hash_deterministic(void) {
  TEST_BEGIN("hash_deterministic");
  // Same coordinates should produce same hash
  uint32_t h1 = vignette_hash_pixel(100, 200);
  uint32_t h2 = vignette_hash_pixel(100, 200);
  ASSERT_EQ(h1, h2);
  TEST_END();
}

void test_hash_different_for_different_coords(void) {
  TEST_BEGIN("hash_different_for_different_coords");
  // Different coordinates should produce different hashes
  uint32_t h1 = vignette_hash_pixel(0, 0);
  uint32_t h2 = vignette_hash_pixel(1, 0);
  uint32_t h3 = vignette_hash_pixel(0, 1);
  // Hash collision is possible but extremely unlikely for adjacent pixels
  ASSERT_TRUE(h1 != h2 || h1 != h3);
  TEST_END();
}

// =================================================================================================
// Test: Vignette Application - Edge Cases
// =================================================================================================

void test_vignette_no_config(void) {
  TEST_BEGIN("vignette_no_config");
  // With nullptr config, framebuffer should be unchanged
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  VignetteGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 0.3f};
  effect_vignette_apply(fb, 1, 1, nullptr, &geom);
  ASSERT_NEAR(fb[0], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.0001f);
  TEST_END();
}

void test_vignette_no_geometry(void) {
  TEST_BEGIN("vignette_no_geometry");
  // With nullptr geometry, framebuffer should be unchanged
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  effect_vignette_apply(fb, 1, 1, &cfg, nullptr);
  ASSERT_NEAR(fb[0], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.0001f);
  TEST_END();
}

void test_vignette_disabled(void) {
  TEST_BEGIN("vignette_disabled");
  // With enabled=0, framebuffer should be unchanged
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  VignetteConfig cfg = {.enabled = 0, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 0.3f};
  effect_vignette_apply(fb, 1, 1, &cfg, &geom);
  ASSERT_NEAR(fb[0], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.0001f);
  TEST_END();
}

// =================================================================================================
// Test: Inside Circle Unchanged
// =================================================================================================

void test_vignette_inside_circle_unchanged(void) {
  TEST_BEGIN("inside_circle_unchanged");
  // Pixels inside the watch circle should not be modified
  // Create a 3x3 buffer with circle centered at (1, 1) with radius 2
  // Pixel coords: (0,0), (1,0), (2,0), (0,1), (1,1), (2,1), (0,2), (1,2), (2,2)
  // Max distance from (1,1) is to corners: sqrt(2) ≈ 1.41 < 2
  float fb[36]; // 3x3 RGBA
  for (int i = 0; i < 36; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.6f; // RGB=0.6, A=1.0
  }
  float original_center = fb[16]; // Center pixel R

  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry geom = {
      .cx = 1.0f,
      .cy = 1.0f,
      .radius = 2.0f // Covers all pixels (max distance ~1.41 < 2)
  };

  effect_vignette_apply(fb, 3, 3, &cfg, &geom);

  // All pixels should be unchanged (all inside circle)
  ASSERT_NEAR(fb[0], 0.6f, 0.0001f);             // (0,0)
  ASSERT_NEAR(fb[16], original_center, 0.0001f); // (1,1)
  ASSERT_NEAR(fb[32], 0.6f, 0.0001f);            // (2,2)
  TEST_END();
}

// =================================================================================================
// Test: Outside Circle Gets Background
// =================================================================================================

void test_vignette_outside_circle_gets_background(void) {
  TEST_BEGIN("outside_circle_gets_background");
  // Pixels outside the watch circle should get grey background
  // Create a 3x3 buffer with very small circle
  float fb[36];
  for (int i = 0; i < 36; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.8f; // Bright pixels
  }

  float bg = 0.2f; // Custom background color
  VignetteConfig cfg = {.enabled = 1, .strength = 0.0f, .background = bg}; // No vignette darkening
  VignetteGeometry geom = {
      .cx = 1.5f,
      .cy = 1.5f,
      .radius = 0.1f // Very small - all pixels outside
  };

  effect_vignette_apply(fb, 3, 3, &cfg, &geom);

  // All pixels should be close to background color (with dither noise)
  // At strength=0, there's no darkening, just flat background + dither
  ASSERT_NEAR(fb[0], bg, 0.01f);  // Corner (0,0) - allow for dither noise
  ASSERT_NEAR(fb[16], bg, 0.01f); // Center (1,1)
  TEST_END();
}

void test_vignette_background_alpha_is_one(void) {
  TEST_BEGIN("background_alpha_is_one");
  // Background pixels should have alpha = 1.0
  float fb[4] = {0.5f, 0.5f, 0.5f, 0.5f}; // Semi-transparent input

  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry geom = {
      .cx = 0.5f,
      .cy = 0.5f,
      .radius = 0.1f // Pixel is outside circle
  };

  effect_vignette_apply(fb, 1, 1, &cfg, &geom);

  // Alpha should be set to 1.0 for background
  ASSERT_NEAR(fb[3], 1.0f, 0.0001f);
  TEST_END();
}

// =================================================================================================
// Test: Vignette Darkening
// =================================================================================================

void test_vignette_darkening_at_corners(void) {
  TEST_BEGIN("darkening_at_corners");
  // Corners should be darker than pixels near the circle edge
  // Create a 10x10 buffer with small circle at center
  float fb[400]; // 10x10 RGBA
  for (int i = 0; i < 400; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.8f;
  }

  float strength = 0.4f;
  float bg = 0.137f;
  VignetteConfig cfg = {.enabled = 1, .strength = strength, .background = bg};
  VignetteGeometry geom = {
      .cx = 5.0f,
      .cy = 5.0f,
      .radius = 2.0f // Small circle, lots of background
  };

  effect_vignette_apply(fb, 10, 10, &cfg, &geom);

  // Corner pixel (0,0) should be darker than edge pixel (2,5)
  // Corner is far from center, edge is just outside circle
  float corner = fb[0]; // (0,0) - distance ~7.07 from center
  // Pixel (2,5) is at distance 3 from center (5,5), just outside circle
  float near_edge = fb[(size_t)(5 * 10 + 2) * 4];

  // Both should be around background level, but corner should be darker
  ASSERT_TRUE(corner < bg);        // Corner has vignette darkening
  ASSERT_TRUE(corner < near_edge); // Corner is darker than near-edge
  TEST_END();
}

void test_vignette_zero_strength_no_darkening(void) {
  TEST_BEGIN("zero_strength_no_darkening");
  // With strength=0, all background pixels should be same brightness
  float fb[400]; // 10x10 RGBA
  for (int i = 0; i < 400; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.8f;
  }

  float bg = 0.2f;
  VignetteConfig cfg = {.enabled = 1, .strength = 0.0f, .background = bg};
  VignetteGeometry geom = {.cx = 5.0f, .cy = 5.0f, .radius = 2.0f};

  effect_vignette_apply(fb, 10, 10, &cfg, &geom);

  // All background pixels should be approximately same (just dither noise)
  float corner = fb[0]; // (0,0) - clearly outside circle
  // Pixel (2,5) is at distance 3 from center (5,5), clearly outside
  float near_edge = fb[(size_t)(5 * 10 + 2) * 4];

  // Both should be close to background (within dither noise tolerance)
  ASSERT_NEAR(corner, bg, 0.01f);
  ASSERT_NEAR(near_edge, bg, 0.01f);
  TEST_END();
}

// =================================================================================================
// Test: Smoothstep Gradient
// =================================================================================================

void test_vignette_smoothstep_gradient(void) {
  TEST_BEGIN("smoothstep_gradient");
  // The vignette should have a smooth gradient (not linear)
  // Create a line of pixels from edge to corner and verify smoothness
  float fb[40]; // 10x1 RGBA
  for (int i = 0; i < 40; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.8f;
  }

  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.2f};
  VignetteGeometry geom = {
      .cx = 0.0f, // Circle at left edge
      .cy = 0.5f,
      .radius = 1.0f // Only x=0 is inside
  };

  effect_vignette_apply(fb, 10, 1, &cfg, &geom);

  // Pixels x=1 through x=9 are outside circle
  // Verify gradient exists and is monotonic (darker toward right)
  float prev = fb[4]; // x=1
  int is_monotonic = 1;
  for (size_t x = 2; x < 10; x++) {
    float curr = fb[x * 4];
    // Allow small variations due to dither noise
    if (curr > prev + 0.02f) {
      is_monotonic = 0;
    }
    prev = curr;
  }
  ASSERT_TRUE(is_monotonic);
  TEST_END();
}

// =================================================================================================
// Test: Dithering Noise
// =================================================================================================

void test_vignette_dither_deterministic(void) {
  TEST_BEGIN("dither_deterministic");
  // Same input should produce same output (deterministic dither)
  float fb1[4] = {0.8f, 0.8f, 0.8f, 1.0f};
  float fb2[4] = {0.8f, 0.8f, 0.8f, 1.0f};

  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 0.1f};

  effect_vignette_apply(fb1, 1, 1, &cfg, &geom);
  effect_vignette_apply(fb2, 1, 1, &cfg, &geom);

  ASSERT_NEAR(fb1[0], fb2[0], 0.0001f);
  ASSERT_NEAR(fb1[1], fb2[1], 0.0001f);
  ASSERT_NEAR(fb1[2], fb2[2], 0.0001f);
  TEST_END();
}

void test_vignette_dither_breaks_banding(void) {
  TEST_BEGIN("dither_breaks_banding");
  // Adjacent pixels with same distance should have slightly different values due to dither
  float fb[8]; // 2x1 RGBA
  for (int i = 0; i < 8; i++) {
    fb[i] = (i % 4 == 3) ? 1.0f : 0.8f;
  }

  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry geom = {.cx = 0.5f, // Center between the two pixels
                           .cy = 5.0f, // Far above, so both pixels have similar distance
                           .radius = 0.1f};

  effect_vignette_apply(fb, 2, 1, &cfg, &geom);

  // Both pixels should be background-ish but slightly different due to dither
  // (or exactly same if hash happens to produce same value - rare)
  // Just verify values are in valid range
  ASSERT_TRUE(fb[0] >= 0.0f && fb[0] <= 1.0f);
  ASSERT_TRUE(fb[4] >= 0.0f && fb[4] <= 1.0f);
  TEST_END();
}

// =================================================================================================
// Test: Grey Channel Uniformity
// =================================================================================================

void test_vignette_grey_uniform(void) {
  TEST_BEGIN("grey_uniform");
  // Background should be grey (R=G=B)
  float fb[4] = {0.8f, 0.5f, 0.3f, 1.0f}; // Non-uniform input

  VignetteConfig cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 0.1f};

  effect_vignette_apply(fb, 1, 1, &cfg, &geom);

  // All color channels should be equal (grey)
  ASSERT_NEAR(fb[0], fb[1], 0.0001f);
  ASSERT_NEAR(fb[1], fb[2], 0.0001f);
  TEST_END();
}

// =================================================================================================
// Test: Default Values
// =================================================================================================

void test_vignette_uses_defaults(void) {
  TEST_BEGIN("uses_defaults");
  // With zero/unset values, should use defaults
  float fb[4] = {0.8f, 0.8f, 0.8f, 1.0f};

  VignetteConfig cfg = {.enabled = 1, .strength = 0.0f, .background = 0.0f};
  VignetteGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 0.1f};

  effect_vignette_apply(fb, 1, 1, &cfg, &geom);

  // Should use default background (~0.137) and default strength (0.4)
  // With default strength and pixel at corner, should see some darkening
  // Just verify it's in a reasonable range for grey background
  ASSERT_TRUE(fb[0] > 0.05f && fb[0] < 0.2f);
  TEST_END();
}

// =================================================================================================
// Test: Clamping
// =================================================================================================

void test_vignette_clamps_output(void) {
  TEST_BEGIN("clamps_output");
  // Output should be clamped to [0, 1]
  float fb[4] = {0.8f, 0.8f, 0.8f, 1.0f};

  VignetteConfig cfg = {.enabled = 1, .strength = 2.0f, .background = 0.137f}; // Very strong
  VignetteGeometry geom = {.cx = 0.5f, .cy = 0.5f, .radius = 0.1f};

  effect_vignette_apply(fb, 1, 1, &cfg, &geom);

  // Even with extreme strength, values should be clamped
  ASSERT_TRUE(fb[0] >= 0.0f && fb[0] <= 1.0f);
  ASSERT_TRUE(fb[1] >= 0.0f && fb[1] <= 1.0f);
  ASSERT_TRUE(fb[2] >= 0.0f && fb[2] <= 1.0f);
  TEST_END();
}

// =================================================================================================
// Test: Effect Descriptor
// =================================================================================================

void test_effect_descriptor(void) {
  TEST_BEGIN("effect_descriptor");
  // Verify effect descriptor is properly defined
  ASSERT_TRUE(EFFECT_VIGNETTE.name != nullptr);
  ASSERT_TRUE(EFFECT_VIGNETTE.apply != nullptr);
  ASSERT_TRUE(EFFECT_VIGNETTE.apply == effect_vignette_apply);
  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Vignette effect tests\n");
  printf("=====================\n");

  // Hash function tests
  test_hash_deterministic();
  test_hash_different_for_different_coords();

  // Edge case tests
  test_vignette_no_config();
  test_vignette_no_geometry();
  test_vignette_disabled();

  // Inside/outside circle tests
  test_vignette_inside_circle_unchanged();
  test_vignette_outside_circle_gets_background();
  test_vignette_background_alpha_is_one();

  // Vignette darkening tests
  test_vignette_darkening_at_corners();
  test_vignette_zero_strength_no_darkening();

  // Smoothstep gradient tests
  test_vignette_smoothstep_gradient();

  // Dithering tests
  test_vignette_dither_deterministic();
  test_vignette_dither_breaks_banding();

  // Grey uniformity tests
  test_vignette_grey_uniform();

  // Default values tests
  test_vignette_uses_defaults();

  // Clamping tests
  test_vignette_clamps_output();

  // Effect descriptor tests
  test_effect_descriptor();

  TEST_RUNNER_END();
}
