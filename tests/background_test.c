// Test harness for background layer module

#include "layers/background.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Basic Initialization
// =================================================================================================

void test_background_inside_circle(void) {
  TEST_BEGIN("background_inside_circle");

  // 10x10 framebuffer with circle at center, radius 4
  float fb[10 * 10 * 4];
  RenderContext ctx = {.fb = fb, .width = 10, .height = 10, .cx = 5.0f, .cy = 5.0f, .radius = 4.0f};

  layer_background_render(&ctx);

  // Center pixel (5,5) should be opaque black
  int idx = (5 * 10 + 5) * 4;
  ASSERT_NEAR(fb[idx], 0.0f, 0.001f);     // R
  ASSERT_NEAR(fb[idx + 1], 0.0f, 0.001f); // G
  ASSERT_NEAR(fb[idx + 2], 0.0f, 0.001f); // B
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  TEST_END();
}

void test_background_outside_circle(void) {
  TEST_BEGIN("background_outside_circle");

  float fb[10 * 10 * 4];
  RenderContext ctx = {.fb = fb, .width = 10, .height = 10, .cx = 5.0f, .cy = 5.0f, .radius = 4.0f};

  layer_background_render(&ctx);

  // Corner pixel (0,0) should be opaque white (for e-ink displays)
  int idx = 0;
  ASSERT_NEAR(fb[idx], 1.0f, 0.001f);     // R
  ASSERT_NEAR(fb[idx + 1], 1.0f, 0.001f); // G
  ASSERT_NEAR(fb[idx + 2], 1.0f, 0.001f); // B
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  TEST_END();
}

void test_background_circle_edge(void) {
  TEST_BEGIN("background_circle_edge");

  float fb[10 * 10 * 4];
  RenderContext ctx = {.fb = fb, .width = 10, .height = 10, .cx = 5.0f, .cy = 5.0f, .radius = 4.0f};

  layer_background_render(&ctx);

  // Pixel at (5, 1) is exactly at radius=4 from center (5,5), should be inside (black)
  // Distance: |1 - 5| = 4, so dist^2 = 16, radius^2 = 16
  int idx = (1 * 10 + 5) * 4;
  ASSERT_NEAR(fb[idx], 0.0f, 0.001f);     // R = 0 (black inside)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (inside, on edge)

  // Pixel at (5, 0) is at distance 5 from center, should be outside (white)
  idx = (0 * 10 + 5) * 4;
  ASSERT_NEAR(fb[idx], 1.0f, 0.001f);     // R = 1 (white outside)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  TEST_END();
}

// =================================================================================================
// Test: Inside/Outside Color Values
// =================================================================================================

void test_background_inside_outside_colors(void) {
  TEST_BEGIN("background_inside_outside_colors");

  float fb[6 * 6 * 4];
  RenderContext ctx = {.fb = fb, .width = 6, .height = 6, .cx = 3.0f, .cy = 3.0f, .radius = 2.5f};

  layer_background_render(&ctx);

  // Inside pixels should be black, outside pixels should be white
  float r2 = 2.5f * 2.5f;
  for (int y = 0; y < 6; y++) {
    for (int x = 0; x < 6; x++) {
      float dx = (float)x - 3.0f;
      float dy = (float)y - 3.0f;
      float dist2 = dx * dx + dy * dy;
      int idx = (y * 6 + x) * 4;

      if (dist2 <= r2) {
        // Inside: black
        ASSERT_NEAR(fb[idx], 0.0f, 0.001f);
        ASSERT_NEAR(fb[idx + 1], 0.0f, 0.001f);
        ASSERT_NEAR(fb[idx + 2], 0.0f, 0.001f);
      } else {
        // Outside: white
        ASSERT_NEAR(fb[idx], 1.0f, 0.001f);
        ASSERT_NEAR(fb[idx + 1], 1.0f, 0.001f);
        ASSERT_NEAR(fb[idx + 2], 1.0f, 0.001f);
      }
    }
  }

  TEST_END();
}

// =================================================================================================
// Test: Alpha Pattern
// =================================================================================================

void test_background_alpha_pattern(void) {
  TEST_BEGIN("background_alpha_pattern");

  // 8x8 framebuffer with circle centered at (4,4) radius 3
  float fb[8 * 8 * 4] = {0};
  RenderContext ctx = {.fb = fb, .width = 8, .height = 8, .cx = 4.0f, .cy = 4.0f, .radius = 3.0f};

  layer_background_render(&ctx);

  int black_count = 0;
  int white_count = 0;

  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      int idx = (y * 8 + x) * 4;

      // All pixels should be opaque
      ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f);

      // Count black (inside) vs white (outside)
      if (fb[idx] < 0.5f) {
        black_count++;
      } else {
        white_count++;
      }
    }
  }

  // Should have both black (inside) and white (outside) pixels
  ASSERT_TRUE(black_count > 0);
  ASSERT_TRUE(white_count > 0);

  TEST_END();
}

// =================================================================================================
// Test: Circle at Different Positions
// =================================================================================================

void test_background_offset_circle(void) {
  TEST_BEGIN("background_offset_circle");

  float fb[10 * 10 * 4];
  RenderContext ctx = {.fb = fb,
                       .width = 10,
                       .height = 10,
                       .cx = 2.0f, // Circle in upper-left area
                       .cy = 2.0f,
                       .radius = 2.0f};

  layer_background_render(&ctx);

  // (2,2) is at center, should be opaque black
  int idx = (2 * 10 + 2) * 4;
  ASSERT_NEAR(fb[idx], 0.0f, 0.001f);     // R = 0 (black)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  // (8,8) is far from center, should be opaque white
  idx = (8 * 10 + 8) * 4;
  ASSERT_NEAR(fb[idx], 1.0f, 0.001f);     // R = 1 (white)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  TEST_END();
}

void test_background_large_radius(void) {
  TEST_BEGIN("background_large_radius");

  float fb[6 * 6 * 4];
  RenderContext ctx = {
      .fb = fb,
      .width = 6,
      .height = 6,
      .cx = 3.0f,
      .cy = 3.0f,
      .radius = 10.0f // Larger than image
  };

  layer_background_render(&ctx);

  // All pixels should be inside (alpha = 1)
  for (int y = 0; y < 6; y++) {
    for (int x = 0; x < 6; x++) {
      int idx = (y * 6 + x) * 4;
      ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f);
    }
  }

  TEST_END();
}

void test_background_zero_radius(void) {
  TEST_BEGIN("background_zero_radius");

  float fb[4 * 4 * 4];
  RenderContext ctx = {
      .fb = fb,
      .width = 4,
      .height = 4,
      .cx = 2.0f,
      .cy = 2.0f,
      .radius = 0.0f // Point circle
  };

  layer_background_render(&ctx);

  // Only center pixel should be black (inside)
  int center_idx = (2 * 4 + 2) * 4;
  ASSERT_NEAR(fb[center_idx], 0.0f, 0.001f);     // R = 0 (black)
  ASSERT_NEAR(fb[center_idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  // All other pixels should be white (outside)
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      if (x != 2 || y != 2) {
        int idx = (y * 4 + x) * 4;
        ASSERT_NEAR(fb[idx], 1.0f, 0.001f);     // R = 1 (white)
        ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)
      }
    }
  }

  TEST_END();
}

// =================================================================================================
// Test: Layer Descriptor
// =================================================================================================

void test_layer_descriptor(void) {
  TEST_BEGIN("layer_descriptor");

  ASSERT_TRUE(LAYER_BACKGROUND.name != nullptr);
  ASSERT_TRUE(LAYER_BACKGROUND.render == layer_background_render);

  TEST_END();
}

// =================================================================================================
// Test: Comparison with Original Implementation
// =================================================================================================

void test_matches_original_center(void) {
  TEST_BEGIN("matches_original_center");

  // Test against expected behavior: black inside circle, white outside
  float fb[20 * 20 * 4];
  RenderContext ctx = {
      .fb = fb, .width = 20, .height = 20, .cx = 10.0f, .cy = 10.0f, .radius = 8.0f};

  layer_background_render(&ctx);

  // Sample points:
  // dist2 = (x - cx)^2 + (y - cy)^2
  // Inside if dist2 <= radius^2 (64)

  // (10, 10): dist2 = 0, inside -> black
  int idx = (10 * 20 + 10) * 4;
  ASSERT_NEAR(fb[idx], 0.0f, 0.001f);     // R = 0 (black)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  // (10, 2): dist2 = 64, inside (on boundary) -> black
  idx = (2 * 20 + 10) * 4;
  ASSERT_NEAR(fb[idx], 0.0f, 0.001f);     // R = 0 (black)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  // (10, 1): dist2 = 81, outside -> white
  idx = (1 * 20 + 10) * 4;
  ASSERT_NEAR(fb[idx], 1.0f, 0.001f);     // R = 1 (white)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  // (14, 14): dist2 = 32, inside -> black
  idx = (14 * 20 + 14) * 4;
  ASSERT_NEAR(fb[idx], 0.0f, 0.001f);     // R = 0 (black)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  // (16, 16): dist2 = 72, outside -> white
  idx = (16 * 20 + 16) * 4;
  ASSERT_NEAR(fb[idx], 1.0f, 0.001f);     // R = 1 (white)
  ASSERT_NEAR(fb[idx + 3], 1.0f, 0.001f); // A = 1 (opaque)

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Background layer tests\n");
  printf("======================\n");

  // Basic initialization
  test_background_inside_circle();
  test_background_outside_circle();
  test_background_circle_edge();

  // Inside/outside colors
  test_background_inside_outside_colors();

  // Alpha pattern
  test_background_alpha_pattern();

  // Circle positions
  test_background_offset_circle();
  test_background_large_radius();
  test_background_zero_radius();

  // Layer descriptor
  test_layer_descriptor();

  // Comparison with original
  test_matches_original_center();

  TEST_RUNNER_END();
}
