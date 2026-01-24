// Test harness for gamma kernel

#include "kernels/gamma.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: sRGB to Linear Conversion
// =================================================================================================

void test_srgb_to_linear_black(void) {
  TEST_BEGIN("srgb_to_linear_black");
  float result = gamma_srgb_to_linear(0);
  ASSERT_NEAR(result, 0.0f, 0.0001f);
  TEST_END();
}

void test_srgb_to_linear_white(void) {
  TEST_BEGIN("srgb_to_linear_white");
  float result = gamma_srgb_to_linear(255);
  ASSERT_NEAR(result, 1.0f, 0.001f);
  TEST_END();
}

void test_srgb_to_linear_mid_gray(void) {
  // sRGB 186 is approximately linear 0.5 (perceptual mid-gray)
  TEST_BEGIN("srgb_to_linear_mid_gray");
  float result = gamma_srgb_to_linear(186);
  ASSERT_NEAR(result, 0.5f, 0.02f);
  TEST_END();
}

void test_srgb_to_linear_low_value(void) {
  // sRGB 10 is in the linear region (< ~10.3)
  TEST_BEGIN("srgb_to_linear_low_value");
  float result = gamma_srgb_to_linear(10);
  float expected = (10.0f / 255.0f) / 12.92f; // Should use linear formula
  ASSERT_NEAR(result, expected, 0.0001f);
  TEST_END();
}

// =================================================================================================
// Test: Linear to sRGB Conversion
// =================================================================================================

void test_linear_to_srgb_black(void) {
  TEST_BEGIN("linear_to_srgb_black");
  float result = gamma_linear_to_srgb(0.0f);
  ASSERT_NEAR(result, 0.0f, 0.0001f);
  TEST_END();
}

void test_linear_to_srgb_white(void) {
  TEST_BEGIN("linear_to_srgb_white");
  float result = gamma_linear_to_srgb(1.0f);
  ASSERT_NEAR(result, 1.0f, 0.0001f);
  TEST_END();
}

void test_linear_to_srgb_mid_gray(void) {
  // Linear 0.5 should be approximately sRGB 0.735 (186/255)
  TEST_BEGIN("linear_to_srgb_mid_gray");
  float result = gamma_linear_to_srgb(0.5f);
  ASSERT_NEAR(result, 0.735f, 0.01f);
  TEST_END();
}

void test_linear_to_srgb_low_value(void) {
  // Below 0.0031308 should use linear formula
  TEST_BEGIN("linear_to_srgb_low_value");
  float input = 0.002f;
  float result = gamma_linear_to_srgb(input);
  float expected = input * 12.92f; // Should use linear formula
  ASSERT_NEAR(result, expected, 0.0001f);
  TEST_END();
}

// =================================================================================================
// Test: Round-trip Consistency
// =================================================================================================

void test_roundtrip_black(void) {
  TEST_BEGIN("roundtrip_black");
  float linear = gamma_srgb_to_linear(0);
  float srgb = gamma_linear_to_srgb(linear);
  ASSERT_NEAR(srgb, 0.0f, 0.001f);
  TEST_END();
}

void test_roundtrip_white(void) {
  TEST_BEGIN("roundtrip_white");
  float linear = gamma_srgb_to_linear(255);
  float srgb = gamma_linear_to_srgb(linear);
  ASSERT_NEAR(srgb, 1.0f, 0.001f);
  TEST_END();
}

void test_srgb_to_linear_monotonic(void) {
  // Verify the gamma curve is monotonic: brighter sRGB -> brighter linear
  // This is more important than exact values for visual correctness
  TEST_BEGIN("srgb_to_linear_monotonic");
  float prev = gamma_srgb_to_linear(0);
  for (int i = 1; i <= 255; i++) {
    float curr = gamma_srgb_to_linear((uint8_t)i);
    ASSERT_TRUE(curr >= prev);
    prev = curr;
  }
  TEST_END();
}

// =================================================================================================
// Test: Kernel Application
// =================================================================================================

void test_kernel_gamma_apply(void) {
  TEST_BEGIN("kernel_gamma_apply");

  // Create a small test framebuffer (2x2 pixels)
  float fb[16] = {// Pixel 0: black (linear)
                  0.0f, 0.0f, 0.0f, 1.0f,
                  // Pixel 1: white (linear)
                  1.0f, 1.0f, 1.0f, 1.0f,
                  // Pixel 2: mid-gray (linear 0.5)
                  0.5f, 0.5f, 0.5f, 1.0f,
                  // Pixel 3: red (linear)
                  0.5f, 0.0f, 0.0f, 1.0f};

  kernel_gamma_apply(fb, 2, 2, (void *)0, (void *)0);

  // Check black stayed black
  ASSERT_NEAR(fb[0], 0.0f, 0.001f);

  // Check white stayed white
  ASSERT_NEAR(fb[4], 1.0f, 0.001f);

  // Check mid-gray got brighter (linear 0.5 -> sRGB ~0.735)
  ASSERT_NEAR(fb[8], 0.735f, 0.02f);

  // Check alpha unchanged
  ASSERT_NEAR(fb[3], 1.0f, 0.001f);
  ASSERT_NEAR(fb[7], 1.0f, 0.001f);

  TEST_END();
}

void test_kernel_gamma_clamps_values(void) {
  TEST_BEGIN("kernel_gamma_clamps_values");

  // Create framebuffer with out-of-range values (from additive blending)
  float fb[4] = {1.5f, -0.2f, 2.0f, 1.0f};

  kernel_gamma_apply(fb, 1, 1, (void *)0, (void *)0);

  // Values should be clamped before gamma conversion
  ASSERT_NEAR(fb[0], 1.0f, 0.001f); // 1.5 clamped to 1.0, then gamma = 1.0
  ASSERT_NEAR(fb[1], 0.0f, 0.001f); // -0.2 clamped to 0.0, then gamma = 0.0
  ASSERT_NEAR(fb[2], 1.0f, 0.001f); // 2.0 clamped to 1.0, then gamma = 1.0

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Gamma kernel tests\n");
  printf("==================\n");

  // sRGB to linear tests
  test_srgb_to_linear_black();
  test_srgb_to_linear_white();
  test_srgb_to_linear_mid_gray();
  test_srgb_to_linear_low_value();

  // Linear to sRGB tests
  test_linear_to_srgb_black();
  test_linear_to_srgb_white();
  test_linear_to_srgb_mid_gray();
  test_linear_to_srgb_low_value();

  // Round-trip and monotonicity tests
  test_roundtrip_black();
  test_roundtrip_white();
  test_srgb_to_linear_monotonic();

  // Kernel tests
  test_kernel_gamma_apply();
  test_kernel_gamma_clamps_values();

  TEST_RUNNER_END();
}
