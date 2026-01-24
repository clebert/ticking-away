// Test harness for kernel pipeline

#include "config.h"
#include "kernels/gamma.h"
#include "kernels/grain.h"
#include "kernels/vignette.h"
#include "pipeline.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Helper: Create test framebuffer
// =================================================================================================

// Fill a framebuffer with a solid color (linear RGB)
static void fill_framebuffer(float *fb, int width, int height, float r, float g, float b, float a) {
  int total = width * height;
  for (int i = 0; i < total; i++) {
    fb[i * 4 + 0] = r;
    fb[i * 4 + 1] = g;
    fb[i * 4 + 2] = b;
    fb[i * 4 + 3] = a;
  }
}

// =================================================================================================
// Test: Pipeline Initialization
// =================================================================================================

void test_pipeline_init(void) {
  TEST_BEGIN("pipeline_init");
  Pipeline p;
  pipeline_init(&p);
  ASSERT_EQ(pipeline_count(&p), 0);
  TEST_END();
}

void test_pipeline_add_kernel(void) {
  TEST_BEGIN("pipeline_add_kernel");
  Pipeline p;
  pipeline_init(&p);

  int result = pipeline_add_kernel(&p, &KERNEL_GAMMA, (void *)0, (void *)0);
  ASSERT_EQ(result, 0);
  ASSERT_EQ(pipeline_count(&p), 1);

  result = pipeline_add_kernel(&p, &KERNEL_GRAIN, (void *)0, (void *)0);
  ASSERT_EQ(result, 0);
  ASSERT_EQ(pipeline_count(&p), 2);

  TEST_END();
}

void test_pipeline_add_null_kernel(void) {
  TEST_BEGIN("pipeline_add_null_kernel");
  Pipeline p;
  pipeline_init(&p);

  int result = pipeline_add_kernel(&p, (void *)0, (void *)0, (void *)0);
  ASSERT_EQ(result, -1);            // Should fail
  ASSERT_EQ(pipeline_count(&p), 0); // Count unchanged

  TEST_END();
}

void test_pipeline_full(void) {
  TEST_BEGIN("pipeline_full");
  Pipeline p;
  pipeline_init(&p);

  // Fill the pipeline to capacity
  for (int i = 0; i < PIPELINE_MAX_KERNELS; i++) {
    int result = pipeline_add_kernel(&p, &KERNEL_GAMMA, (void *)0, (void *)0);
    ASSERT_EQ(result, 0);
  }
  ASSERT_EQ(pipeline_count(&p), PIPELINE_MAX_KERNELS);

  // Try to add one more - should fail
  int result = pipeline_add_kernel(&p, &KERNEL_GAMMA, (void *)0, (void *)0);
  ASSERT_EQ(result, -1);
  ASSERT_EQ(pipeline_count(&p), PIPELINE_MAX_KERNELS); // Count unchanged

  TEST_END();
}

// =================================================================================================
// Test: Pipeline Execution
// =================================================================================================

void test_pipeline_execute_empty(void) {
  TEST_BEGIN("pipeline_execute_empty");
  Pipeline p;
  pipeline_init(&p);

  // Execute empty pipeline - should not crash
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  pipeline_execute(&p, fb, 1, 1);

  // Framebuffer unchanged
  ASSERT_NEAR(fb[0], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[1], 0.5f, 0.0001f);
  ASSERT_NEAR(fb[2], 0.5f, 0.0001f);

  TEST_END();
}

void test_pipeline_execute_single_kernel(void) {
  TEST_BEGIN("pipeline_execute_single_kernel");
  Pipeline p;
  pipeline_init(&p);
  pipeline_add_kernel(&p, &KERNEL_GAMMA, (void *)0, (void *)0);

  // Linear gray (0.5) should become sRGB gray (~0.735)
  float fb[4] = {0.5f, 0.5f, 0.5f, 1.0f};
  pipeline_execute(&p, fb, 1, 1);

  ASSERT_NEAR(fb[0], 0.735f, 0.02f);
  ASSERT_NEAR(fb[1], 0.735f, 0.02f);
  ASSERT_NEAR(fb[2], 0.735f, 0.02f);
  ASSERT_NEAR(fb[3], 1.0f, 0.0001f); // Alpha unchanged

  TEST_END();
}

void test_pipeline_execute_gamma_then_grain(void) {
  TEST_BEGIN("pipeline_execute_gamma_then_grain");
  Pipeline p;
  pipeline_init(&p);

  // Add gamma kernel first
  pipeline_add_kernel(&p, &KERNEL_GAMMA, (void *)0, (void *)0);

  // Add grain kernel with config
  GrainConfig grain_cfg = {.intensity = 0.1f, .scale = 1.0f, .threshold = 0.01f, .prism_only = 0};
  GrainGeometry grain_geom = {.cx = 2.0f, .cy = 2.0f, .radius = 10.0f, .prism_vertices = (void *)0};
  pipeline_add_kernel(&p, &KERNEL_GRAIN, &grain_cfg, &grain_geom);

  ASSERT_EQ(pipeline_count(&p), 2);

  // Create 4x4 framebuffer filled with mid-gray (linear)
  float fb[64];
  fill_framebuffer(fb, 4, 4, 0.5f, 0.5f, 0.5f, 1.0f);

  pipeline_execute(&p, fb, 4, 4);

  // After gamma: ~0.735 (sRGB mid-gray)
  // After grain: slightly modified (grain adds noise based on position)
  // The exact values depend on grain hash, but should be near 0.735 +/- grain_intensity
  for (int i = 0; i < 16; i++) {
    float r = fb[i * 4 + 0];
    float g = fb[i * 4 + 1];
    float b = fb[i * 4 + 2];
    // Values should be within grain intensity range of gamma-corrected value
    ASSERT_TRUE(r >= 0.5f && r <= 1.0f); // Allow for grain noise
    ASSERT_TRUE(g >= 0.5f && g <= 1.0f);
    ASSERT_TRUE(b >= 0.5f && b <= 1.0f);
  }

  TEST_END();
}

void test_pipeline_execute_order_matters(void) {
  TEST_BEGIN("pipeline_execute_order_matters");

  // Execute gamma then vignette
  Pipeline p1;
  pipeline_init(&p1);
  pipeline_add_kernel(&p1, &KERNEL_GAMMA, (void *)0, (void *)0);

  VignetteConfig vignette_cfg = {.enabled = 1, .strength = 0.4f, .background = 0.137f};
  VignetteGeometry vignette_geom = {
      .cx = 2.0f,
      .cy = 2.0f,
      .radius = 0.5f // Very small radius so most pixels are "outside"
  };
  pipeline_add_kernel(&p1, &KERNEL_VIGNETTE, &vignette_cfg, &vignette_geom);

  float fb1[64];
  fill_framebuffer(fb1, 4, 4, 0.5f, 0.5f, 0.5f, 1.0f);
  pipeline_execute(&p1, fb1, 4, 4);

  // Execute vignette then gamma
  Pipeline p2;
  pipeline_init(&p2);
  pipeline_add_kernel(&p2, &KERNEL_VIGNETTE, &vignette_cfg, &vignette_geom);
  pipeline_add_kernel(&p2, &KERNEL_GAMMA, (void *)0, (void *)0);

  float fb2[64];
  fill_framebuffer(fb2, 4, 4, 0.5f, 0.5f, 0.5f, 1.0f);
  pipeline_execute(&p2, fb2, 4, 4);

  // Results should be different because order matters
  // (vignette replaces pixels outside circle with background color)
  // We check that at least one pixel differs
  int any_different = 0;
  for (int i = 0; i < 64; i++) {
    float diff = fb1[i] - fb2[i];
    if (diff < 0)
      diff = -diff;
    if (diff > 0.01f) {
      any_different = 1;
      break;
    }
  }
  ASSERT_TRUE(any_different);

  TEST_END();
}

// =================================================================================================
// Test: Multiple kernel execution
// =================================================================================================

void test_pipeline_three_kernels(void) {
  TEST_BEGIN("pipeline_three_kernels");
  Pipeline p;
  pipeline_init(&p);

  // Standard post-processing pipeline: gamma -> grain -> vignette
  pipeline_add_kernel(&p, &KERNEL_GAMMA, (void *)0, (void *)0);

  GrainConfig grain_cfg = {.intensity = 0.05f, .scale = 1.0f, .threshold = 0.01f, .prism_only = 0};
  GrainGeometry grain_geom = {
      .cx = 4.0f, .cy = 4.0f, .radius = 100.0f, .prism_vertices = (void *)0};
  pipeline_add_kernel(&p, &KERNEL_GRAIN, &grain_cfg, &grain_geom);

  VignetteConfig vignette_cfg = {.enabled = 1, .strength = 0.3f, .background = 0.1f};
  VignetteGeometry vignette_geom = {.cx = 4.0f, .cy = 4.0f, .radius = 3.0f};
  pipeline_add_kernel(&p, &KERNEL_VIGNETTE, &vignette_cfg, &vignette_geom);

  ASSERT_EQ(pipeline_count(&p), 3);

  // Create 8x8 framebuffer with gradient
  float fb[256];
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      int idx = (y * 8 + x) * 4;
      float v = (float)(x + y) / 14.0f; // 0.0 to 1.0 gradient
      fb[idx + 0] = v;
      fb[idx + 1] = v;
      fb[idx + 2] = v;
      fb[idx + 3] = 1.0f;
    }
  }

  pipeline_execute(&p, fb, 8, 8);

  // Verify all values are in valid range
  for (int i = 0; i < 64; i++) {
    ASSERT_TRUE(fb[i * 4 + 0] >= 0.0f && fb[i * 4 + 0] <= 1.0f);
    ASSERT_TRUE(fb[i * 4 + 1] >= 0.0f && fb[i * 4 + 1] <= 1.0f);
    ASSERT_TRUE(fb[i * 4 + 2] >= 0.0f && fb[i * 4 + 2] <= 1.0f);
  }

  TEST_END();
}

// =================================================================================================
// Test: Config and cache passing
// =================================================================================================

void test_pipeline_passes_config_and_cache(void) {
  TEST_BEGIN("pipeline_passes_config_and_cache");
  Pipeline p;
  pipeline_init(&p);

  // Grain with zero intensity should not modify the framebuffer much
  GrainConfig grain_cfg_off = {
      .intensity = 0.0f, .scale = 1.0f, .threshold = 0.01f, .prism_only = 0};
  GrainGeometry grain_geom = {.cx = 2.0f, .cy = 2.0f, .radius = 10.0f, .prism_vertices = (void *)0};
  pipeline_add_kernel(&p, &KERNEL_GRAIN, &grain_cfg_off, &grain_geom);

  float fb[16];
  fill_framebuffer(fb, 2, 2, 0.5f, 0.6f, 0.7f, 1.0f);

  float original_r = fb[0];
  float original_g = fb[1];
  float original_b = fb[2];

  pipeline_execute(&p, fb, 2, 2);

  // With zero intensity, grain should not change values
  ASSERT_NEAR(fb[0], original_r, 0.0001f);
  ASSERT_NEAR(fb[1], original_g, 0.0001f);
  ASSERT_NEAR(fb[2], original_b, 0.0001f);

  TEST_END();
}

void test_pipeline_disabled_vignette(void) {
  TEST_BEGIN("pipeline_disabled_vignette");
  Pipeline p;
  pipeline_init(&p);

  // Disabled vignette should not modify framebuffer
  VignetteConfig vignette_cfg = {.enabled = 0, .strength = 0.5f, .background = 0.2f};
  VignetteGeometry vignette_geom = {.cx = 2.0f, .cy = 2.0f, .radius = 1.0f};
  pipeline_add_kernel(&p, &KERNEL_VIGNETTE, &vignette_cfg, &vignette_geom);

  float fb[16];
  fill_framebuffer(fb, 2, 2, 0.3f, 0.4f, 0.5f, 1.0f);

  float original_r = fb[0];
  float original_g = fb[1];
  float original_b = fb[2];

  pipeline_execute(&p, fb, 2, 2);

  // Disabled vignette should not change values
  ASSERT_NEAR(fb[0], original_r, 0.0001f);
  ASSERT_NEAR(fb[1], original_g, 0.0001f);
  ASSERT_NEAR(fb[2], original_b, 0.0001f);

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Pipeline tests\n");
  printf("==============\n\n");

  // Initialization tests
  test_pipeline_init();
  test_pipeline_add_kernel();
  test_pipeline_add_null_kernel();
  test_pipeline_full();

  // Execution tests
  test_pipeline_execute_empty();
  test_pipeline_execute_single_kernel();
  test_pipeline_execute_gamma_then_grain();
  test_pipeline_execute_order_matters();
  test_pipeline_three_kernels();

  // Config/cache tests
  test_pipeline_passes_config_and_cache();
  test_pipeline_disabled_vignette();

  TEST_RUNNER_END();
}
