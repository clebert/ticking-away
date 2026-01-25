// =================================================================================================
// Rays Layer Tests
// =================================================================================================
// Tests for ray path computation, color palette handling, and layer rendering.

#include <math.h>
#include <stdio.h>

#include "config.h"
#include "effects/effect.h"
#include "geometry/prism.h"
#include "geometry/types.h"
#include "layers/layer.h"
#include "layers/rays.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test Helpers
// =================================================================================================

// Create a standard test prism (60 degree apex, centered at given point)
static void create_test_prism(float cx, float cy, float size, Prism *prism) {
  prism_create(cx, cy, size, 60.0f, prism);
}

// =================================================================================================
// Palette Cache Tests (5.3a)
// =================================================================================================

void test_palette_cache_init(void) {
  TEST_BEGIN("palette_cache_init");

  RaysPaletteCache cache = {0};
  cache.initialized = 0;
  cache.palette = -1;

  rays_init_palette_cache(&cache, 0);

  ASSERT_EQ(cache.initialized, 1);
  ASSERT_EQ(cache.palette, 0);

  TEST_END();
}

void test_palette_cache_reinit_same(void) {
  TEST_BEGIN("palette_cache_reinit_same");

  RaysPaletteCache cache = {0};

  rays_init_palette_cache(&cache, 0);
  float original_r = cache.linear[0].r;

  // Reinitialize with same palette - should be no-op
  rays_init_palette_cache(&cache, 0);
  ASSERT_NEAR(cache.linear[0].r, original_r, 0.0001f);

  TEST_END();
}

void test_palette_cache_reinit_different(void) {
  TEST_BEGIN("palette_cache_reinit_different");

  RaysPaletteCache cache = {0};

  rays_init_palette_cache(&cache, 0); // OKLCH_BALANCED

  rays_init_palette_cache(&cache, 1); // SATURATED
  ASSERT_EQ(cache.palette, 1);

  // Red band should be different (pure red in SATURATED)
  // SATURATED red is (255, 0, 0) -> linear should be 1.0
  ASSERT_NEAR(cache.linear[0].r, 1.0f, 0.001f);

  TEST_END();
}

void test_palette_cache_invalid_palette(void) {
  TEST_BEGIN("palette_cache_invalid_palette");

  RaysPaletteCache cache = {0};

  // Invalid palette should clamp to 0
  rays_init_palette_cache(&cache, 100);
  ASSERT_EQ(cache.palette, 0);

  cache.initialized = 0;
  rays_init_palette_cache(&cache, -5);
  ASSERT_EQ(cache.palette, 0);

  TEST_END();
}

void test_get_band_color_valid(void) {
  TEST_BEGIN("get_band_color_valid");

  RaysPaletteCache cache = {0};
  rays_init_palette_cache(&cache, 1); // SATURATED

  RaysRGBLinear red = rays_get_band_color(&cache, 0);
  ASSERT_NEAR(red.r, 1.0f, 0.001f);
  ASSERT_NEAR(red.g, 0.0f, 0.001f);
  ASSERT_NEAR(red.b, 0.0f, 0.001f);

  RaysRGBLinear violet = rays_get_band_color(&cache, 6);
  ASSERT_TRUE(violet.r > 0.0f); // Has red component
  ASSERT_NEAR(violet.g, 0.0f, 0.001f);
  ASSERT_TRUE(violet.b > 0.0f); // Has blue component

  TEST_END();
}

void test_get_band_color_invalid(void) {
  TEST_BEGIN("get_band_color_invalid");

  RaysPaletteCache cache = {0};
  rays_init_palette_cache(&cache, 0);

  RaysRGBLinear out_of_bounds = rays_get_band_color(&cache, -1);
  ASSERT_NEAR(out_of_bounds.r, 0.0f, 0.001f);

  out_of_bounds = rays_get_band_color(&cache, 100);
  ASSERT_NEAR(out_of_bounds.r, 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Color Interpolation Tests
// =================================================================================================

void test_interpolate_color_endpoints(void) {
  TEST_BEGIN("interpolate_color_endpoints");

  RaysPaletteCache cache = {0};
  rays_init_palette_cache(&cache, 1); // SATURATED for clearer results

  // t=0 should be close to red band
  RaysRGBLinear at_0 = rays_interpolate_color(&cache, 0.0f);
  ASSERT_NEAR(at_0.r, cache.linear[0].r, 0.01f);

  // t=1 should be close to violet band
  RaysRGBLinear at_1 = rays_interpolate_color(&cache, 1.0f);
  ASSERT_NEAR(at_1.b, cache.linear[6].b, 0.1f); // Violet has blue

  TEST_END();
}

void test_interpolate_color_midpoint(void) {
  TEST_BEGIN("interpolate_color_midpoint");

  RaysPaletteCache cache = {0};
  rays_init_palette_cache(&cache, 0);

  // t=0.5 should be somewhere between bands (greenish)
  RaysRGBLinear mid = rays_interpolate_color(&cache, 0.5f);
  // The middle of the spectrum should have significant green
  ASSERT_TRUE(mid.g > 0.1f);

  TEST_END();
}

void test_interpolate_color_extrapolate_infrared(void) {
  TEST_BEGIN("interpolate_color_extrapolate_infrared");

  RaysPaletteCache cache = {0};
  rays_init_palette_cache(&cache, 0);

  // t < 0 should extrapolate toward infrared (darker red)
  RaysRGBLinear infrared = rays_interpolate_color(&cache, -0.5f);
  // Should be reddish
  ASSERT_TRUE(infrared.r > infrared.g);
  ASSERT_TRUE(infrared.r > infrared.b);

  TEST_END();
}

void test_interpolate_color_extrapolate_ultraviolet(void) {
  TEST_BEGIN("interpolate_color_extrapolate_ultraviolet");

  RaysPaletteCache cache = {0};
  rays_init_palette_cache(&cache, 0);

  // t > 1 should extrapolate toward ultraviolet (purple)
  RaysRGBLinear uv = rays_interpolate_color(&cache, 1.5f);
  // Should have blue component
  ASSERT_TRUE(uv.b > 0.0f);

  TEST_END();
}

// =================================================================================================
// Ray Path Computation Tests (5.3b)
// =================================================================================================

void test_ray_paths_12_00(void) {
  TEST_BEGIN("ray_paths_12_00");

  // 12:00 - Minute hand at top (12 o'clock)
  Prism prism;
  float cx = 200.0f, cy = 200.0f, radius = 180.0f;
  create_test_prism(cx, cy, 100.0f, &prism);

  // At 12:00, minute is at top, pointing toward center
  float minute_angle = -3.14159f / 2.0f; // -PI/2 = 12 o'clock
  float entry_x = cx + cosf(minute_angle) * radius;
  float entry_y = cy + sinf(minute_angle) * radius;

  // Hour at 12:00 as well
  float hour_angle = minute_angle;

  RaysPaths paths = rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle,
                                       0.5f, // Some spread
                                       &prism);

  ASSERT_TRUE(paths.hits_prism);
  ASSERT_TRUE(paths.entry_ray.valid);

  TEST_END();
}

void test_ray_paths_3_15(void) {
  TEST_BEGIN("ray_paths_3_15");

  // 3:15 - Minute at 15 (3 o'clock position)
  Prism prism;
  float cx = 200.0f, cy = 200.0f, radius = 180.0f;
  create_test_prism(cx, cy, 100.0f, &prism);

  float pi_f = 3.14159265f;
  // 15 minutes = 1/4 of circle from 12 o'clock
  float minute_angle = -pi_f / 2.0f + (15.0f / 60.0f) * 2.0f * pi_f;
  float entry_x = cx + cosf(minute_angle) * radius;
  float entry_y = cy + sinf(minute_angle) * radius;

  // Hour at 3:15 (3 hours + 15 minutes interpolation)
  float hour_angle =
      -pi_f / 2.0f + (3.0f / 12.0f) * 2.0f * pi_f + (15.0f / 60.0f) * (2.0f * pi_f / 12.0f);

  RaysPaths paths = rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle, 0.5f, &prism);

  ASSERT_TRUE(paths.hits_prism);

  // All bands should have valid exit rays
  for (int i = 0; i < RAYS_NUM_BANDS; i++) {
    ASSERT_TRUE(paths.bands[i].internal_seg1.valid);
  }

  TEST_END();
}

void test_ray_paths_7_14(void) {
  TEST_BEGIN("ray_paths_7_14");

  // 7:14 - A case where rays cross through the prism interior
  Prism prism;
  float cx = 200.0f, cy = 200.0f, radius = 180.0f;
  create_test_prism(cx, cy, 100.0f, &prism);

  float pi_f = 3.14159265f;
  float minute_angle = -pi_f / 2.0f + (14.0f / 60.0f) * 2.0f * pi_f;
  float entry_x = cx + cosf(minute_angle) * radius;
  float entry_y = cy + sinf(minute_angle) * radius;

  float hour_angle =
      -pi_f / 2.0f + (7.0f / 12.0f) * 2.0f * pi_f + (14.0f / 60.0f) * (2.0f * pi_f / 12.0f);

  RaysPaths paths = rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle, 0.5f, &prism);

  ASSERT_TRUE(paths.hits_prism);

  TEST_END();
}

void test_ray_paths_10_45(void) {
  TEST_BEGIN("ray_paths_10_45");

  // 10:45 - Minute at 45 (9 o'clock position)
  Prism prism;
  float cx = 200.0f, cy = 200.0f, radius = 180.0f;
  create_test_prism(cx, cy, 100.0f, &prism);

  float pi_f = 3.14159265f;
  float minute_angle = -pi_f / 2.0f + (45.0f / 60.0f) * 2.0f * pi_f;
  float entry_x = cx + cosf(minute_angle) * radius;
  float entry_y = cy + sinf(minute_angle) * radius;

  float hour_angle =
      -pi_f / 2.0f + (10.0f / 12.0f) * 2.0f * pi_f + (45.0f / 60.0f) * (2.0f * pi_f / 12.0f);

  RaysPaths paths = rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle, 0.5f, &prism);

  ASSERT_TRUE(paths.hits_prism);

  TEST_END();
}

void test_ray_paths_no_spread(void) {
  TEST_BEGIN("ray_paths_no_spread");

  // Test with rainbow_spread = 0 (all rays exit same direction)
  Prism prism;
  float cx = 200.0f, cy = 200.0f, radius = 180.0f;
  create_test_prism(cx, cy, 100.0f, &prism);

  float pi_f = 3.14159265f;
  float minute_angle = -pi_f / 2.0f + 0.25f * 2.0f * pi_f; // 3 o'clock
  float entry_x = cx + cosf(minute_angle) * radius;
  float entry_y = cy + sinf(minute_angle) * radius;
  float hour_angle = minute_angle;

  RaysPaths paths = rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle,
                                       0.0f, // No spread
                                       &prism);

  if (paths.hits_prism) {
    // With no spread, gradient should not be valid
    ASSERT_FALSE(paths.gradient_valid);

    // All bands should have same exit angle
    float first_angle = paths.bands[0].exit_angle;
    for (int i = 1; i < RAYS_NUM_BANDS; i++) {
      ASSERT_NEAR(paths.bands[i].exit_angle, first_angle, 0.001f);
    }
  }

  TEST_END();
}

void test_ray_paths_max_spread(void) {
  TEST_BEGIN("ray_paths_max_spread");

  // Test with rainbow_spread = 1 (maximum 30 degree spread)
  Prism prism;
  float cx = 200.0f, cy = 200.0f, radius = 180.0f;
  create_test_prism(cx, cy, 100.0f, &prism);

  float pi_f = 3.14159265f;
  float minute_angle = 0.0f; // 3 o'clock
  float entry_x = cx + cosf(minute_angle) * radius;
  float entry_y = cy + sinf(minute_angle) * radius;
  float hour_angle = pi_f / 4.0f; // 45 degrees

  RaysPaths paths = rays_compute_paths(cx, cy, radius, entry_x, entry_y, hour_angle,
                                       1.0f, // Maximum spread
                                       &prism);

  if (paths.hits_prism && paths.gradient_valid) {
    // Exit angles should span about 30 degrees with centered spacing
    float angle_diff = paths.bands[RAYS_NUM_BANDS - 1].exit_angle - paths.bands[0].exit_angle;
    if (angle_diff < 0)
      angle_diff = -angle_diff;
    // Should be approximately (N-1)/N * 30 degrees
    float expected_span =
        ((float)(RAYS_NUM_BANDS - 1) / (float)RAYS_NUM_BANDS) * (30.0f * pi_f / 180.0f);
    ASSERT_NEAR(angle_diff, expected_span, 0.05f);
  }

  TEST_END();
}

// =================================================================================================
// Layer Rendering Tests
// =================================================================================================

void test_layer_render_null_context(void) {
  TEST_BEGIN("layer_render_null_context");

  RenderContext ctx = {0}; // NOLINT(modernize-use-nullptr)

  // Should not crash with null fields
  layer_rays_render(&ctx);

  // If we get here without crashing, test passes
  ASSERT_TRUE(1);

  TEST_END();
}

void test_layer_render_basic(void) {
  TEST_BEGIN("layer_render_basic");

  // Basic rendering test - just verify it doesn't crash
  float fb[400 * 400 * 4];
  for (int i = 0; i < 400 * 400 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &prism);

  PrismConfig prism_cfg = {.size = 0.5f, .rainbow_spread = 0.5f};

  RayConfig ray_cfg = {.glow_width = 0.02f,
                       .intensity = 1.0f,
                       .falloff = FALLOFF_QUADRATIC,
                       .palette = 0,
                       .gradient_fill = 0,
                       .reverse = 0};

  RenderContext ctx = {.fb = fb,
                       .width = 400,
                       .height = 400,
                       .cx = 200.0f,
                       .cy = 200.0f,
                       .radius = 180.0f,
                       .prism = &prism,
                       .time_minutes = 195.0f, // 3:15
                       .prism_config = &prism_cfg,
                       .ray_config = &ray_cfg,
                       .glow_config = nullptr,
                       .marker_config = nullptr};

  layer_rays_render(&ctx);

  // Check that something was drawn (some pixels should be non-zero)
  int has_content = 0;
  for (int i = 0; i < 400 * 400 * 4; i++) {
    if (fb[i] > 0.001f) {
      has_content = 1;
      break;
    }
  }
  ASSERT_TRUE(has_content);

  TEST_END();
}

void test_layer_render_with_gradient(void) {
  TEST_BEGIN("layer_render_with_gradient");

  // Test rendering with gradient fill enabled
  float fb[400 * 400 * 4];
  for (int i = 0; i < 400 * 400 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &prism);

  PrismConfig prism_cfg = {.size = 0.5f, .rainbow_spread = 0.5f};

  RayConfig ray_cfg = {.glow_width = 0.02f,
                       .intensity = 1.0f,
                       .falloff = FALLOFF_QUADRATIC,
                       .palette = 0,
                       .gradient_fill = 1, // Enable gradient
                       .reverse = 0};

  RenderContext ctx = {.fb = fb,
                       .width = 400,
                       .height = 400,
                       .cx = 200.0f,
                       .cy = 200.0f,
                       .radius = 180.0f,
                       .prism = &prism,
                       .time_minutes = 195.0f, // 3:15
                       .prism_config = &prism_cfg,
                       .ray_config = &ray_cfg,
                       .glow_config = nullptr,
                       .marker_config = nullptr};

  layer_rays_render(&ctx);

  // Should have pixels filled with gradient
  int colored_pixels = 0;
  for (int i = 0; i < 400 * 400; i++) {
    int idx = i * 4;
    if (fb[idx] > 0.01f || fb[idx + 1] > 0.01f || fb[idx + 2] > 0.01f) {
      colored_pixels++;
    }
  }
  // Gradient should fill significant area
  ASSERT_TRUE(colored_pixels > 1000);

  TEST_END();
}

void test_layer_render_reverse_spectrum(void) {
  TEST_BEGIN("layer_render_reverse_spectrum");

  // Test rendering with reverse spectrum
  float fb1[400 * 400 * 4];
  float fb2[400 * 400 * 4];
  for (int i = 0; i < 400 * 400 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  Prism prism;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &prism);

  PrismConfig prism_cfg = {.rainbow_spread = 0.5f};
  RayConfig ray_cfg = {.glow_width = 0.02f,
                       .intensity = 1.0f,
                       .falloff = FALLOFF_QUADRATIC,
                       .palette = 0,
                       .gradient_fill = 0,
                       .reverse = 0};
  RayConfig ray_cfg_rev = ray_cfg;
  ray_cfg_rev.reverse = 1;

  RenderContext ctx = {.fb = fb1,
                       .width = 400,
                       .height = 400,
                       .cx = 200.0f,
                       .cy = 200.0f,
                       .radius = 180.0f,
                       .prism = &prism,
                       .time_minutes = 195.0f,
                       .prism_config = &prism_cfg,
                       .ray_config = &ray_cfg};

  layer_rays_render(&ctx);

  ctx.fb = fb2;
  ctx.ray_config = &ray_cfg_rev;
  layer_rays_render(&ctx);

  // Buffers should be different when reverse is toggled
  int different = 0;
  for (int i = 0; i < 400 * 400 * 4; i++) {
    float diff = fb1[i] - fb2[i];
    if (diff < 0)
      diff = -diff;
    if (diff > 0.01f) {
      different = 1;
      break;
    }
  }
  ASSERT_TRUE(different);

  TEST_END();
}

void test_layer_descriptor(void) {
  TEST_BEGIN("layer_descriptor");

  ASSERT_TRUE(LAYER_RAYS.name != nullptr);
  ASSERT_TRUE(LAYER_RAYS.render == layer_rays_render);

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Rays layer tests\n");
  printf("================\n");

  // Palette cache tests
  test_palette_cache_init();
  test_palette_cache_reinit_same();
  test_palette_cache_reinit_different();
  test_palette_cache_invalid_palette();
  test_get_band_color_valid();
  test_get_band_color_invalid();

  // Color interpolation tests
  test_interpolate_color_endpoints();
  test_interpolate_color_midpoint();
  test_interpolate_color_extrapolate_infrared();
  test_interpolate_color_extrapolate_ultraviolet();

  // Ray path computation tests
  test_ray_paths_12_00();
  test_ray_paths_3_15();
  test_ray_paths_7_14();
  test_ray_paths_10_45();
  test_ray_paths_no_spread();
  test_ray_paths_max_spread();

  // Layer rendering tests
  test_layer_render_null_context();
  test_layer_render_basic();
  test_layer_render_with_gradient();
  test_layer_render_reverse_spectrum();
  test_layer_descriptor();

  TEST_RUNNER_END();
}
