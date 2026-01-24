// =================================================================================================
// Scene Tests
// =================================================================================================
// Tests for the Scene abstraction layer.

#include <stdio.h>

#include "config.h"
#include "geometry/types.h"
#include "kernels/kernel.h"
#include "scene.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test Framebuffer
// =================================================================================================

#define TEST_WIDTH 100
#define TEST_HEIGHT 100
#define FB_SIZE (TEST_WIDTH * TEST_HEIGHT * 4)

static float test_fb[FB_SIZE];

static void clear_fb(void) {
  for (int i = 0; i < FB_SIZE; i++) {
    test_fb[i] = 0.0f;
  }
}

// =================================================================================================
// Initialization Tests
// =================================================================================================

void test_scene_init_dimensions(void) {
  TEST_BEGIN("scene_init_dimensions");

  Scene scene;
  scene_init(&scene, 200, 100);

  ASSERT_EQ(scene.width, 200);
  ASSERT_EQ(scene.height, 100);
  ASSERT_NEAR(scene.radius, 50.0f, 0.01f); // min(200,100)/2
  ASSERT_NEAR(scene.cx, 100.0f, 0.01f);    // width/2
  ASSERT_NEAR(scene.cy, 50.0f, 0.01f);     // height/2

  TEST_END();
}

void test_scene_init_square(void) {
  TEST_BEGIN("scene_init_square");

  Scene scene;
  scene_init(&scene, 400, 400);

  ASSERT_EQ(scene.width, 400);
  ASSERT_EQ(scene.height, 400);
  ASSERT_NEAR(scene.radius, 200.0f, 0.01f);
  ASSERT_NEAR(scene.cx, 200.0f, 0.01f);
  ASSERT_NEAR(scene.cy, 200.0f, 0.01f);

  TEST_END();
}

void test_scene_init_default_time(void) {
  TEST_BEGIN("scene_init_default_time");

  Scene scene;
  scene_init(&scene, 100, 100);

  ASSERT_NEAR(scene.time_minutes, 0.0f, 0.01f); // Default is 12:00

  TEST_END();
}

void test_scene_init_prism_dirty(void) {
  TEST_BEGIN("scene_init_prism_dirty");

  Scene scene;
  scene_init(&scene, 100, 100);

  ASSERT_EQ(scene.prism_dirty, 1);

  TEST_END();
}

// =================================================================================================
// Time Configuration Tests
// =================================================================================================

void test_scene_set_time_basic(void) {
  TEST_BEGIN("scene_set_time_basic");

  Scene scene;
  scene_init(&scene, 100, 100);

  scene_set_time(&scene, 3, 15.0f);
  ASSERT_NEAR(scene.time_minutes, 195.0f, 0.01f); // 3*60 + 15

  TEST_END();
}

void test_scene_set_time_wrap_hour(void) {
  TEST_BEGIN("scene_set_time_wrap_hour");

  Scene scene;
  scene_init(&scene, 100, 100);

  scene_set_time(&scene, 14, 30.0f);              // 14 -> 2 (14 % 12 = 2)
  ASSERT_NEAR(scene.time_minutes, 150.0f, 0.01f); // 2*60 + 30

  TEST_END();
}

void test_scene_set_time_minutes_basic(void) {
  TEST_BEGIN("scene_set_time_minutes_basic");

  Scene scene;
  scene_init(&scene, 100, 100);

  scene_set_time_minutes(&scene, 450.0f); // 7:30
  ASSERT_NEAR(scene.time_minutes, 450.0f, 0.01f);

  TEST_END();
}

void test_scene_set_time_minutes_wrap(void) {
  TEST_BEGIN("scene_set_time_minutes_wrap");

  Scene scene;
  scene_init(&scene, 100, 100);

  scene_set_time_minutes(&scene, 750.0f);        // Wraps at 720
  ASSERT_NEAR(scene.time_minutes, 30.0f, 0.01f); // 750 - 720 = 30

  TEST_END();
}

// =================================================================================================
// Configuration Tests
// =================================================================================================

void test_scene_set_prism_config(void) {
  TEST_BEGIN("scene_set_prism_config");

  Scene scene;
  scene_init(&scene, 100, 100);

  // Clear dirty flag
  scene_update_prism(&scene);
  ASSERT_EQ(scene.prism_dirty, 0);

  // Set new config
  PrismConfig cfg = {.size = 0.8f, .rainbow_spread = 0.7f, .blue_tint = 0.1f, .gray = 0.3f};
  scene_set_prism_config(&scene, &cfg);

  ASSERT_NEAR(scene.prism_config.size, 0.8f, 0.01f);
  ASSERT_NEAR(scene.prism_config.rainbow_spread, 0.7f, 0.01f);
  ASSERT_EQ(scene.prism_dirty, 1); // Should be marked dirty

  TEST_END();
}

void test_scene_set_glow_config(void) {
  TEST_BEGIN("scene_set_glow_config");

  Scene scene;
  scene_init(&scene, 100, 100);

  GlowConfig cfg = {
      .r = 255, .g = 128, .b = 64, .width = 0.2f, .intensity = 0.9f, .falloff = FALLOFF_CUBIC};
  scene_set_glow_config(&scene, &cfg);

  ASSERT_EQ(scene.glow_config.r, 255);
  ASSERT_EQ(scene.glow_config.g, 128);
  ASSERT_EQ(scene.glow_config.b, 64);
  ASSERT_NEAR(scene.glow_config.width, 0.2f, 0.01f);

  TEST_END();
}

void test_scene_set_ray_config(void) {
  TEST_BEGIN("scene_set_ray_config");

  Scene scene;
  scene_init(&scene, 100, 100);

  RayConfig cfg = {.glow_width = 0.05f,
                   .intensity = 0.6f,
                   .falloff = FALLOFF_LINEAR,
                   .palette = 2,
                   .gradient_fill = 1,
                   .reverse = 0};
  scene_set_ray_config(&scene, &cfg);

  ASSERT_NEAR(scene.ray_config.glow_width, 0.05f, 0.01f);
  ASSERT_EQ(scene.ray_config.palette, 2);
  ASSERT_EQ(scene.ray_config.gradient_fill, 1);

  TEST_END();
}

void test_scene_set_marker_config(void) {
  TEST_BEGIN("scene_set_marker_config");

  Scene scene;
  scene_init(&scene, 100, 100);

  MarkerConfig cfg = {.visible = 0,
                      .length = 0.1f,
                      .glow_width = 0.02f,
                      .glow_intensity = 0.5f,
                      .falloff = FALLOFF_QUADRATIC};
  scene_set_marker_config(&scene, &cfg);

  ASSERT_EQ(scene.marker_config.visible, 0);
  ASSERT_NEAR(scene.marker_config.length, 0.1f, 0.01f);

  TEST_END();
}

// =================================================================================================
// Prism Tests
// =================================================================================================

void test_scene_update_prism(void) {
  TEST_BEGIN("scene_update_prism");

  Scene scene;
  scene_init(&scene, 100, 100);

  ASSERT_EQ(scene.prism_dirty, 1);

  scene_update_prism(&scene);

  ASSERT_EQ(scene.prism_dirty, 0);

  // Prism should be valid
  const Prism *p = scene_get_prism(&scene);
  ASSERT_TRUE(p != 0);

  TEST_END();
}

void test_scene_get_prism(void) {
  TEST_BEGIN("scene_get_prism");

  Scene scene;
  scene_init(&scene, 100, 100);
  scene_update_prism(&scene);

  const Prism *p = scene_get_prism(&scene);
  ASSERT_TRUE(p == &scene.prism);

  TEST_END();
}

// =================================================================================================
// Rendering Tests
// =================================================================================================

void test_scene_render_clears_prism_dirty(void) {
  TEST_BEGIN("scene_render_clears_prism_dirty");

  Scene scene;
  scene_init(&scene, TEST_WIDTH, TEST_HEIGHT);
  clear_fb();

  ASSERT_EQ(scene.prism_dirty, 1);

  scene_render_linear(&scene, test_fb);

  ASSERT_EQ(scene.prism_dirty, 0); // Should be cleared after render

  TEST_END();
}

void test_scene_render_sets_background(void) {
  TEST_BEGIN("scene_render_sets_background");

  Scene scene;
  scene_init(&scene, TEST_WIDTH, TEST_HEIGHT);
  clear_fb();

  scene_render_linear(&scene, test_fb);

  // Center pixel should be opaque (alpha=1) since it's inside the circle
  int center_idx = (TEST_HEIGHT / 2 * TEST_WIDTH + TEST_WIDTH / 2) * 4;
  ASSERT_NEAR(test_fb[center_idx + 3], 1.0f, 0.01f); // Alpha = 1

  // Corner pixel should be transparent (alpha=0) since it's outside the circle
  int corner_idx = 0;
  ASSERT_NEAR(test_fb[corner_idx + 3], 0.0f, 0.01f); // Alpha = 0

  TEST_END();
}

void test_scene_render_produces_output(void) {
  TEST_BEGIN("scene_render_produces_output");

  Scene scene;
  scene_init(&scene, TEST_WIDTH, TEST_HEIGHT);
  scene_set_time(&scene, 3, 15.0f); // 3:15 - should produce rays
  clear_fb();

  scene_render_linear(&scene, test_fb);

  // Check that some pixels have color (not all black)
  int has_color = 0;
  for (int i = 0; i < FB_SIZE; i += 4) {
    if (test_fb[i] > 0.01f || test_fb[i + 1] > 0.01f || test_fb[i + 2] > 0.01f) {
      has_color = 1;
      break;
    }
  }
  ASSERT_TRUE(has_color);

  TEST_END();
}

void test_scene_render_at_different_times(void) {
  TEST_BEGIN("scene_render_at_different_times");

  Scene scene;
  scene_init(&scene, TEST_WIDTH, TEST_HEIGHT);
  clear_fb();

  // Render at 12:00
  scene_set_time(&scene, 0, 0.0f);
  scene_render_linear(&scene, test_fb);

  // Render at 6:00 (different ray configuration)
  clear_fb();
  scene_set_time(&scene, 6, 0.0f);
  scene_render_linear(&scene, test_fb);

  // Verify we didn't crash
  ASSERT_TRUE(1);

  TEST_END();
}

// =================================================================================================
// Test Runner
// =================================================================================================

int main(void) {
  printf("Scene Tests\n");
  printf("===========\n\n");

  // Initialization
  test_scene_init_dimensions();
  test_scene_init_square();
  test_scene_init_default_time();
  test_scene_init_prism_dirty();

  // Time
  test_scene_set_time_basic();
  test_scene_set_time_wrap_hour();
  test_scene_set_time_minutes_basic();
  test_scene_set_time_minutes_wrap();

  // Configuration
  test_scene_set_prism_config();
  test_scene_set_glow_config();
  test_scene_set_ray_config();
  test_scene_set_marker_config();

  // Prism
  test_scene_update_prism();
  test_scene_get_prism();

  // Rendering
  test_scene_render_clears_prism_dirty();
  test_scene_render_sets_background();
  test_scene_render_produces_output();
  test_scene_render_at_different_times();

  TEST_RUNNER_END();
}
