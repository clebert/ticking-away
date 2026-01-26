// Test harness for pixel drawing module

#include "draw/pixel.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Falloff Functions
// =================================================================================================

void test_falloff_linear(void) {
  TEST_BEGIN("falloff_linear");

  ASSERT_NEAR(compute_falloff(FALLOFF_LINEAR, 0.0f), 1.0f, 0.001f); // Center
  ASSERT_NEAR(compute_falloff(FALLOFF_LINEAR, 0.5f), 0.5f, 0.001f); // Mid
  ASSERT_NEAR(compute_falloff(FALLOFF_LINEAR, 1.0f), 0.0f, 0.001f); // Edge

  TEST_END();
}

void test_falloff_quadratic(void) {
  TEST_BEGIN("falloff_quadratic");

  ASSERT_NEAR(compute_falloff(FALLOFF_QUADRATIC, 0.0f), 1.0f, 0.001f);  // Center
  ASSERT_NEAR(compute_falloff(FALLOFF_QUADRATIC, 0.5f), 0.25f, 0.001f); // Mid: 0.5^2
  ASSERT_NEAR(compute_falloff(FALLOFF_QUADRATIC, 1.0f), 0.0f, 0.001f);  // Edge

  TEST_END();
}

void test_falloff_cubic(void) {
  TEST_BEGIN("falloff_cubic");

  ASSERT_NEAR(compute_falloff(FALLOFF_CUBIC, 0.0f), 1.0f, 0.001f);   // Center
  ASSERT_NEAR(compute_falloff(FALLOFF_CUBIC, 0.5f), 0.125f, 0.001f); // Mid: 0.5^3
  ASSERT_NEAR(compute_falloff(FALLOFF_CUBIC, 1.0f), 0.0f, 0.001f);   // Edge

  TEST_END();
}

void test_falloff_exponential(void) {
  TEST_BEGIN("falloff_exponential");

  ASSERT_NEAR(compute_falloff(FALLOFF_EXPONENTIAL, 0.0f), 1.0f, 0.001f); // Center
  ASSERT_NEAR(compute_falloff(FALLOFF_EXPONENTIAL, 1.0f), 0.0f, 0.001f); // Edge
  // Mid value should be between 0 and 1
  float mid = compute_falloff(FALLOFF_EXPONENTIAL, 0.5f);
  ASSERT_TRUE(mid > 0.0f && mid < 1.0f);

  TEST_END();
}

void test_falloff_default(void) {
  TEST_BEGIN("falloff_default");

  // Unknown type should default to quadratic
  ASSERT_NEAR(compute_falloff((FalloffType)99, 0.5f), 0.25f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Additive Blending (pixel_add)
// =================================================================================================

void test_pixel_add_basic(void) {
  TEST_BEGIN("pixel_add_basic");

  float fb[16] = {0}; // 2x2 image
  int width = 2, height = 2;

  pixel_add(fb, width, height, 0, 0, 1.0f, 0.5f, 0.25f, 1.0f);

  ASSERT_NEAR(fb[0], 1.0f, 0.001f);  // R
  ASSERT_NEAR(fb[1], 0.5f, 0.001f);  // G
  ASSERT_NEAR(fb[2], 0.25f, 0.001f); // B
  ASSERT_NEAR(fb[3], 0.0f, 0.001f);  // A unchanged

  TEST_END();
}

void test_pixel_add_accumulate(void) {
  TEST_BEGIN("pixel_add_accumulate");

  float fb[16] = {0};
  int width = 2, height = 2;

  // Add twice to same pixel
  pixel_add(fb, width, height, 0, 0, 0.3f, 0.3f, 0.3f, 1.0f);
  pixel_add(fb, width, height, 0, 0, 0.2f, 0.2f, 0.2f, 1.0f);

  ASSERT_NEAR(fb[0], 0.5f, 0.001f); // 0.3 + 0.2
  ASSERT_NEAR(fb[1], 0.5f, 0.001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.001f);

  TEST_END();
}

void test_pixel_add_alpha_scale(void) {
  TEST_BEGIN("pixel_add_alpha_scale");

  float fb[16] = {0};
  int width = 2, height = 2;

  pixel_add(fb, width, height, 0, 0, 1.0f, 1.0f, 1.0f, 0.5f);

  ASSERT_NEAR(fb[0], 0.5f, 0.001f); // 1.0 * 0.5
  ASSERT_NEAR(fb[1], 0.5f, 0.001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.001f);

  TEST_END();
}

void test_pixel_add_out_of_bounds(void) {
  TEST_BEGIN("pixel_add_out_of_bounds");

  float fb[16] = {0};
  int width = 2, height = 2;

  // These should be silently ignored
  pixel_add(fb, width, height, -1, 0, 1.0f, 1.0f, 1.0f, 1.0f);
  pixel_add(fb, width, height, 0, -1, 1.0f, 1.0f, 1.0f, 1.0f);
  pixel_add(fb, width, height, 2, 0, 1.0f, 1.0f, 1.0f, 1.0f);
  pixel_add(fb, width, height, 0, 2, 1.0f, 1.0f, 1.0f, 1.0f);

  // Framebuffer should be unchanged
  for (int i = 0; i < 16; i++) {
    ASSERT_NEAR(fb[i], 0.0f, 0.001f);
  }

  TEST_END();
}

// =================================================================================================
// Test: Alpha Blending (pixel_blend)
// =================================================================================================

void test_pixel_blend_full_alpha(void) {
  TEST_BEGIN("pixel_blend_full_alpha");

  float fb[16] = {0.5f, 0.5f, 0.5f, 1.0f, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  int width = 2, height = 2;

  pixel_blend(fb, width, height, 0, 0, 1.0f, 0.0f, 0.0f, 1.0f);

  ASSERT_NEAR(fb[0], 1.0f, 0.001f); // Fully replaced
  ASSERT_NEAR(fb[1], 0.0f, 0.001f);
  ASSERT_NEAR(fb[2], 0.0f, 0.001f);
  ASSERT_NEAR(fb[3], 1.0f, 0.001f);

  TEST_END();
}

void test_pixel_blend_zero_alpha(void) {
  TEST_BEGIN("pixel_blend_zero_alpha");

  float fb[16] = {0.5f, 0.5f, 0.5f, 1.0f, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  int width = 2, height = 2;

  pixel_blend(fb, width, height, 0, 0, 1.0f, 0.0f, 0.0f, 0.0f);

  ASSERT_NEAR(fb[0], 0.5f, 0.001f); // Unchanged
  ASSERT_NEAR(fb[1], 0.5f, 0.001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.001f);

  TEST_END();
}

void test_pixel_blend_half_alpha(void) {
  TEST_BEGIN("pixel_blend_half_alpha");

  float fb[16] = {0.0f, 0.0f, 0.0f, 1.0f, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  int width = 2, height = 2;

  pixel_blend(fb, width, height, 0, 0, 1.0f, 1.0f, 1.0f, 0.5f);

  // src * 0.5 + dst * 0.5 = 1.0 * 0.5 + 0.0 * 0.5 = 0.5
  ASSERT_NEAR(fb[0], 0.5f, 0.001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.001f);

  TEST_END();
}

void test_pixel_blend_out_of_bounds(void) {
  TEST_BEGIN("pixel_blend_out_of_bounds");

  float fb[16] = {0.5f, 0.5f, 0.5f, 1.0f, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  int width = 2, height = 2;

  // These should be silently ignored
  pixel_blend(fb, width, height, -1, 0, 1.0f, 0.0f, 0.0f, 1.0f);
  pixel_blend(fb, width, height, 2, 0, 1.0f, 0.0f, 0.0f, 1.0f);

  // First pixel unchanged
  ASSERT_NEAR(fb[0], 0.5f, 0.001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Pixel Indexing
// =================================================================================================

void test_pixel_correct_index(void) {
  TEST_BEGIN("pixel_correct_index");

  float fb[32] = {0}; // 2x4 image
  int width = 2, height = 4;

  // Set pixel at (1, 2) - should be at index (2*2 + 1)*4 = 20
  pixel_add(fb, width, height, 1, 2, 0.123f, 0.0f, 0.0f, 1.0f);

  ASSERT_NEAR(fb[20], 0.123f, 0.001f);

  // Verify other pixels are zero
  ASSERT_NEAR(fb[0], 0.0f, 0.001f);
  ASSERT_NEAR(fb[4], 0.0f, 0.001f);
  ASSERT_NEAR(fb[16], 0.0f, 0.001f);
  ASSERT_NEAR(fb[24], 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Pixel drawing tests\n");
  printf("===================\n");

  // Falloff tests
  test_falloff_linear();
  test_falloff_quadratic();
  test_falloff_cubic();
  test_falloff_exponential();
  test_falloff_default();

  // Additive blending tests
  test_pixel_add_basic();
  test_pixel_add_accumulate();
  test_pixel_add_alpha_scale();
  test_pixel_add_out_of_bounds();

  // Alpha blending tests
  test_pixel_blend_full_alpha();
  test_pixel_blend_zero_alpha();
  test_pixel_blend_half_alpha();
  test_pixel_blend_out_of_bounds();

  // Pixel indexing test
  test_pixel_correct_index();

  TEST_RUNNER_END();
}
