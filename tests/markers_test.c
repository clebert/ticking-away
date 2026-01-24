// =================================================================================================
// Markers Layer Tests
// =================================================================================================
// Tests for hour marker rendering around the watch face.

#include <math.h>
#include <stdio.h>

#include "config.h"
#include "kernels/kernel.h"
#include "layers/layer.h"
#include "layers/markers.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Basic Drawing Tests
// =================================================================================================

void test_markers_draw_no_crash(void) {
  TEST_BEGIN("markers_draw_no_crash");
  float fb[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 1,
                         .length = 0.15f,
                         .glow_width = 0.02f,
                         .glow_intensity = 0.8f,
                         .falloff = FALLOFF_LINEAR};

  // Should not crash
  markers_draw(fb, 64, 64, 32.0f, 32.0f, 28.0f, &config);
  TEST_END();
}

void test_markers_draw_writes_pixels(void) {
  TEST_BEGIN("markers_draw_writes_pixels");
  float fb[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 1,
                         .length = 0.15f,
                         .glow_width = 0.03f,
                         .glow_intensity = 1.0f,
                         .falloff = FALLOFF_LINEAR};

  markers_draw(fb, 64, 64, 32.0f, 32.0f, 28.0f, &config);

  // Should have written some non-zero pixels
  int nonzero = 0;
  for (int i = 0; i < 64 * 64 * 4; i++) {
    if (fb[i] > 0.0f)
      nonzero++;
  }
  ASSERT_TRUE(nonzero > 0);
  TEST_END();
}

void test_markers_draw_white_color(void) {
  TEST_BEGIN("markers_draw_white_color");
  float fb[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 1,
                         .length = 0.15f,
                         .glow_width = 0.03f,
                         .glow_intensity = 1.0f,
                         .falloff = FALLOFF_LINEAR};

  markers_draw(fb, 64, 64, 32.0f, 32.0f, 28.0f, &config);

  // Find a pixel that was written and verify R=G=B (white)
  int found_pixel = 0;
  for (int i = 0; i < 64 * 64; i++) {
    float r = fb[i * 4 + 0];
    if (r > 0.01f) {
      // Should be equal (white)
      float g = fb[i * 4 + 1];
      float b = fb[i * 4 + 2];
      ASSERT_NEAR(r, g, 0.001f);
      ASSERT_NEAR(r, b, 0.001f);
      found_pixel = 1;
      break;
    }
  }
  // Should have found at least one pixel
  ASSERT_TRUE(found_pixel);
  TEST_END();
}

void test_markers_draw_12_markers(void) {
  TEST_BEGIN("markers_draw_12_markers");
  float fb[128 * 128 * 4];
  for (int i = 0; i < 128 * 128 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 1,
                         .length = 0.15f,
                         .glow_width = 0.01f, // Small glow for distinct markers
                         .glow_intensity = 1.0f,
                         .falloff = FALLOFF_LINEAR};

  float cx = 64.0f, cy = 64.0f, radius = 55.0f;
  markers_draw(fb, 128, 128, cx, cy, radius, &config);

  // Check that all 12 hour positions have pixels written
  // Hour positions: h=0 is 12 o'clock (top), h=3 is 3 o'clock (right), etc.
  int markers_found = 0;
  for (int h = 0; h < 12; h++) {
    float angle = ((float)h - 3.0f) * 30.0f * 3.14159265f / 180.0f;
    float outer_r = radius * 0.95f; // Check near the outer end
    int px = (int)(cx + cosf(angle) * outer_r);
    int py = (int)(cy + sinf(angle) * outer_r);

    // Check if this position has any brightness
    if (px >= 0 && px < 128 && py >= 0 && py < 128) {
      int idx = (py * 128 + px) * 4;
      if (fb[idx] > 0.001f) {
        markers_found++;
      }
    }
  }
  // All 12 markers should be present
  ASSERT_EQ(markers_found, 12);
  TEST_END();
}

// =================================================================================================
// Configuration Tests
// =================================================================================================

void test_markers_intensity(void) {
  TEST_BEGIN("markers_intensity");
  float fb1[64 * 64 * 4];
  float fb2[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  MarkerConfig config1 = {.visible = 1,
                          .length = 0.15f,
                          .glow_width = 0.03f,
                          .glow_intensity = 0.5f,
                          .falloff = FALLOFF_LINEAR};

  MarkerConfig config2 = {.visible = 1,
                          .length = 0.15f,
                          .glow_width = 0.03f,
                          .glow_intensity = 1.0f,
                          .falloff = FALLOFF_LINEAR};

  markers_draw(fb1, 64, 64, 32.0f, 32.0f, 28.0f, &config1);
  markers_draw(fb2, 64, 64, 32.0f, 32.0f, 28.0f, &config2);

  // Higher intensity should produce brighter pixels
  float sum1 = 0, sum2 = 0;
  for (int i = 0; i < 64 * 64 * 4; i++) {
    sum1 += fb1[i];
    sum2 += fb2[i];
  }
  ASSERT_TRUE(sum2 > sum1);
  TEST_END();
}

void test_markers_length(void) {
  TEST_BEGIN("markers_length");
  float fb1[64 * 64 * 4];
  float fb2[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  MarkerConfig config1 = {.visible = 1,
                          .length = 0.05f, // Short markers
                          .glow_width = 0.02f,
                          .glow_intensity = 1.0f,
                          .falloff = FALLOFF_LINEAR};

  MarkerConfig config2 = {.visible = 1,
                          .length = 0.20f, // Long markers
                          .glow_width = 0.02f,
                          .glow_intensity = 1.0f,
                          .falloff = FALLOFF_LINEAR};

  markers_draw(fb1, 64, 64, 32.0f, 32.0f, 28.0f, &config1);
  markers_draw(fb2, 64, 64, 32.0f, 32.0f, 28.0f, &config2);

  // Longer markers should have more lit pixels
  int count1 = 0, count2 = 0;
  for (size_t i = 0; i < 64UL * 64UL; i++) {
    if (fb1[i * 4] > 0.001f)
      count1++;
    if (fb2[i * 4] > 0.001f)
      count2++;
  }
  ASSERT_TRUE(count2 > count1);
  TEST_END();
}

void test_markers_glow_width(void) {
  TEST_BEGIN("markers_glow_width");
  float fb1[64 * 64 * 4];
  float fb2[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  MarkerConfig config1 = {.visible = 1,
                          .length = 0.15f,
                          .glow_width = 0.01f, // Thin glow
                          .glow_intensity = 1.0f,
                          .falloff = FALLOFF_LINEAR};

  MarkerConfig config2 = {.visible = 1,
                          .length = 0.15f,
                          .glow_width = 0.05f, // Wide glow
                          .glow_intensity = 1.0f,
                          .falloff = FALLOFF_LINEAR};

  markers_draw(fb1, 64, 64, 32.0f, 32.0f, 28.0f, &config1);
  markers_draw(fb2, 64, 64, 32.0f, 32.0f, 28.0f, &config2);

  // Wider glow should affect more pixels
  int count1 = 0, count2 = 0;
  for (size_t i = 0; i < 64UL * 64UL; i++) {
    if (fb1[i * 4] > 0.001f)
      count1++;
    if (fb2[i * 4] > 0.001f)
      count2++;
  }
  ASSERT_TRUE(count2 > count1);
  TEST_END();
}

void test_markers_falloff_types(void) {
  TEST_BEGIN("markers_falloff_types");
  float fb_linear[64 * 64 * 4];
  float fb_quad[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++) {
    fb_linear[i] = 0.0f;
    fb_quad[i] = 0.0f;
  }

  MarkerConfig config_linear = {.visible = 1,
                                .length = 0.15f,
                                .glow_width = 0.03f,
                                .glow_intensity = 1.0f,
                                .falloff = FALLOFF_LINEAR};

  MarkerConfig config_quad = {.visible = 1,
                              .length = 0.15f,
                              .glow_width = 0.03f,
                              .glow_intensity = 1.0f,
                              .falloff = FALLOFF_QUADRATIC};

  markers_draw(fb_linear, 64, 64, 32.0f, 32.0f, 28.0f, &config_linear);
  markers_draw(fb_quad, 64, 64, 32.0f, 32.0f, 28.0f, &config_quad);

  // Different falloffs should produce different results
  int diff_count = 0;
  for (int i = 0; i < 64 * 64 * 4; i++) {
    if (fabsf(fb_linear[i] - fb_quad[i]) > 0.001f)
      diff_count++;
  }
  ASSERT_TRUE(diff_count > 0);
  TEST_END();
}

// =================================================================================================
// Layer Interface Tests
// =================================================================================================

void test_layer_render_null_config(void) {
  TEST_BEGIN("layer_render_null_config");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.0f;

  RenderContext ctx = {
      .fb = fb,
      .width = 32,
      .height = 32,
      .cx = 16.0f,
      .cy = 16.0f,
      .radius = 14.0f,
      .marker_config = nullptr // No config
  };

  // Should not crash with null config
  layer_markers_render(&ctx);

  // Should not have written anything
  float sum = 0;
  for (int i = 0; i < 32 * 32 * 4; i++)
    sum += fb[i];
  ASSERT_NEAR(sum, 0.0f, 0.001f);
  TEST_END();
}

void test_layer_render_invisible(void) {
  TEST_BEGIN("layer_render_invisible");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 0, // Not visible
                         .length = 0.15f,
                         .glow_width = 0.03f,
                         .glow_intensity = 1.0f,
                         .falloff = FALLOFF_LINEAR};

  RenderContext ctx = {.fb = fb,
                       .width = 32,
                       .height = 32,
                       .cx = 16.0f,
                       .cy = 16.0f,
                       .radius = 14.0f,
                       .marker_config = &config};

  // Should not render when visible=0
  layer_markers_render(&ctx);

  // Should not have written anything
  float sum = 0;
  for (int i = 0; i < 32 * 32 * 4; i++)
    sum += fb[i];
  ASSERT_NEAR(sum, 0.0f, 0.001f);
  TEST_END();
}

void test_layer_render_with_config(void) {
  TEST_BEGIN("layer_render_with_config");
  float fb[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 1,
                         .length = 0.15f,
                         .glow_width = 0.03f,
                         .glow_intensity = 0.8f,
                         .falloff = FALLOFF_QUADRATIC};

  RenderContext ctx = {.fb = fb,
                       .width = 64,
                       .height = 64,
                       .cx = 32.0f,
                       .cy = 32.0f,
                       .radius = 28.0f,
                       .marker_config = &config};

  layer_markers_render(&ctx);

  // Should have written some pixels
  int nonzero = 0;
  for (int i = 0; i < 64 * 64 * 4; i++) {
    if (fb[i] > 0.0f)
      nonzero++;
  }
  ASSERT_TRUE(nonzero > 0);
  TEST_END();
}

void test_layer_descriptor(void) {
  TEST_BEGIN("layer_descriptor");
  ASSERT_TRUE(LAYER_MARKERS.name != NULL);
  ASSERT_TRUE(LAYER_MARKERS.render != NULL);
  ASSERT_TRUE(LAYER_MARKERS.render == layer_markers_render);
  TEST_END();
}

// =================================================================================================
// Circle Clipping Tests
// =================================================================================================

void test_markers_clipped_to_circle(void) {
  TEST_BEGIN("markers_clipped_to_circle");
  float fb[64 * 64 * 4];
  for (int i = 0; i < 64 * 64 * 4; i++)
    fb[i] = 0.0f;

  MarkerConfig config = {.visible = 1,
                         .length = 0.15f,
                         .glow_width = 0.03f,
                         .glow_intensity = 1.0f,
                         .falloff = FALLOFF_LINEAR};

  float cx = 32.0f, cy = 32.0f, radius = 20.0f; // Smaller radius
  markers_draw(fb, 64, 64, cx, cy, radius, &config);

  // Pixels far outside the circle should not be affected
  // Check corners
  int corners_clear = 1;
  int corner_positions[][2] = {{0, 0}, {63, 0}, {0, 63}, {63, 63}};
  for (int i = 0; i < 4; i++) {
    int x = corner_positions[i][0];
    int y = corner_positions[i][1];
    int idx = (y * 64 + x) * 4;
    if (fb[idx] > 0.001f) {
      corners_clear = 0;
    }
  }
  ASSERT_TRUE(corners_clear);
  TEST_END();
}

// =================================================================================================
// Test Runner
// =================================================================================================

int main(void) {
  printf("Markers Layer Tests\n");
  printf("===================\n");

  // Basic drawing tests
  test_markers_draw_no_crash();
  test_markers_draw_writes_pixels();
  test_markers_draw_white_color();
  test_markers_draw_12_markers();

  // Configuration tests
  test_markers_intensity();
  test_markers_length();
  test_markers_glow_width();
  test_markers_falloff_types();

  // Layer interface tests
  test_layer_render_null_config();
  test_layer_render_invisible();
  test_layer_render_with_config();
  test_layer_descriptor();

  // Circle clipping tests
  test_markers_clipped_to_circle();

  TEST_RUNNER_END();
}
