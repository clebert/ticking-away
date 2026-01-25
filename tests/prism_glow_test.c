// =================================================================================================
// Prism Glow Layer Tests
// =================================================================================================
// Tests for prism glow rendering, smooth minimum, and edge distance calculations.

#include "config.h"
#include "draw/pixel.h"
#include "geometry/prism.h"
#include "geometry/types.h"
#include "layers/layer.h"
#include "layers/prism_glow.h"
#include "test_harness.h"
#include <math.h>
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Smooth Minimum Tests
// =================================================================================================

void test_smooth_min_equal_values(void) {
  TEST_BEGIN("smooth_min_equal_values");
  float result = smooth_min(5.0f, 5.0f, 1.0f);
  // When a == b with k>0, smooth_min returns slightly less (smoothing effect)
  // Formula: min(a,b) - h*h*k*0.25 where h=1 when a==b
  // So result = 5 - 1*1*1*0.25 = 4.75
  ASSERT_NEAR(result, 4.75f, 0.01f);
  TEST_END();
}

void test_smooth_min_far_apart(void) {
  TEST_BEGIN("smooth_min_far_apart");
  // When values are far apart (> k), smooth_min should return regular min
  float result = smooth_min(1.0f, 10.0f, 1.0f);
  ASSERT_NEAR(result, 1.0f, 0.01f);
  TEST_END();
}

void test_smooth_min_close_values(void) {
  TEST_BEGIN("smooth_min_close_values");
  // When values are close (< k), result should be less than regular min
  float a = 2.0f, b = 2.5f, k = 2.0f;
  float result = smooth_min(a, b, k);
  float hard_min = a < b ? a : b;
  ASSERT_TRUE(result < hard_min);
  TEST_END();
}

void test_smooth_min_commutative(void) {
  TEST_BEGIN("smooth_min_commutative");
  float a = 3.0f, b = 4.0f, k = 1.5f;
  float r1 = smooth_min(a, b, k);
  float r2 = smooth_min(b, a, k);
  ASSERT_NEAR(r1, r2, 0.001f);
  TEST_END();
}

void test_smooth_min_zero_k(void) {
  TEST_BEGIN("smooth_min_zero_k");
  // k=0 should give hard minimum (no smoothing)
  float result = smooth_min(3.0f, 5.0f, 0.0f);
  ASSERT_NEAR(result, 3.0f, 0.001f);
  TEST_END();
}

// =================================================================================================
// Edge Distance Tests
// =================================================================================================

void test_edge_distance_at_center(void) {
  TEST_BEGIN("edge_distance_at_center");
  Prism prism;
  prism_create(50.0f, 50.0f, 30.0f, 60.0f, &prism);

  // Center of prism should be equidistant from all edges
  float dist = prism_min_edge_distance(50.0f, 50.0f, &prism, 5.0f);
  ASSERT_TRUE(dist > 0.0f);
  ASSERT_TRUE(dist < 30.0f); // Should be less than prism size
  TEST_END();
}

void test_edge_distance_near_edge(void) {
  TEST_BEGIN("edge_distance_near_edge");
  Prism prism;
  prism_create(50.0f, 50.0f, 30.0f, 60.0f, &prism);

  // Get a vertex and move slightly inside
  float v0x, v0y, v1x, v1y;
  prism_get_vertex(&prism, 0, &v0x, &v0y);
  prism_get_vertex(&prism, 1, &v1x, &v1y);

  // Midpoint of edge 0-1, moved slightly toward center
  float mx = (v0x + v1x) / 2.0f;
  float my = (v0y + v1y) / 2.0f;
  float cx = 50.0f, cy = 50.0f;
  float px = mx + (cx - mx) * 0.1f; // 10% toward center
  float py = my + (cy - my) * 0.1f;

  float dist = prism_min_edge_distance(px, py, &prism, 5.0f);
  ASSERT_TRUE(dist < 10.0f); // Should be close to the edge
  TEST_END();
}

void test_edge_distance_positive(void) {
  TEST_BEGIN("edge_distance_positive");
  Prism prism;
  prism_create(50.0f, 50.0f, 30.0f, 60.0f, &prism);

  // Multiple points inside prism should have positive distance
  float test_points[][2] = {{50.0f, 50.0f}, {45.0f, 52.0f}, {55.0f, 48.0f}};

  for (int i = 0; i < 3; i++) {
    float dist = prism_min_edge_distance(test_points[i][0], test_points[i][1], &prism, 5.0f);
    ASSERT_TRUE(dist >= 0.0f);
  }
  TEST_END();
}

// =================================================================================================
// Glow Drawing Tests
// =================================================================================================

void test_glow_draw_no_crash(void) {
  TEST_BEGIN("glow_draw_no_crash");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  // Should not crash
  prism_glow_draw(fb, 32, 32, &prism, 0.5f, 0.5f, 0.5f, 5.0f, 1.0f, FALLOFF_LINEAR);
  TEST_END();
}

void test_glow_draw_writes_pixels(void) {
  TEST_BEGIN("glow_draw_writes_pixels");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  prism_glow_draw(fb, 32, 32, &prism, 1.0f, 0.5f, 0.0f, 5.0f, 1.0f, FALLOFF_LINEAR);

  // Should have written some non-zero pixels
  int nonzero = 0;
  for (int i = 0; i < 32 * 32 * 4; i++) {
    if (fb[i] > 0.0f)
      nonzero++;
  }
  ASSERT_TRUE(nonzero > 0);
  TEST_END();
}

void test_glow_draw_additive(void) {
  TEST_BEGIN("glow_draw_additive");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.1f; // Pre-fill with some value

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  prism_glow_draw(fb, 32, 32, &prism, 1.0f, 0.0f, 0.0f, 5.0f, 1.0f, FALLOFF_LINEAR);

  // Inside the prism, R channel should be > 0.1 (additive)
  // Check center pixel
  int cx = 16, cy = 16;
  int idx = (cy * 32 + cx) * 4;
  ASSERT_TRUE(fb[idx] > 0.1f); // R should have increased
  TEST_END();
}

void test_glow_draw_intensity(void) {
  TEST_BEGIN("glow_draw_intensity");
  float fb1[32 * 32 * 4];
  float fb2[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  // Draw with different intensities
  prism_glow_draw(fb1, 32, 32, &prism, 1.0f, 1.0f, 1.0f, 5.0f, 0.5f, FALLOFF_LINEAR);
  prism_glow_draw(fb2, 32, 32, &prism, 1.0f, 1.0f, 1.0f, 5.0f, 1.0f, FALLOFF_LINEAR);

  // Higher intensity should produce brighter pixels
  float sum1 = 0, sum2 = 0;
  for (int i = 0; i < 32 * 32 * 4; i++) {
    sum1 += fb1[i];
    sum2 += fb2[i];
  }
  ASSERT_TRUE(sum2 > sum1);
  TEST_END();
}

void test_glow_draw_glow_width(void) {
  TEST_BEGIN("glow_draw_glow_width");
  float fb1[32 * 32 * 4];
  float fb2[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++) {
    fb1[i] = 0.0f;
    fb2[i] = 0.0f;
  }

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  // Draw with different glow widths
  prism_glow_draw(fb1, 32, 32, &prism, 1.0f, 1.0f, 1.0f, 2.0f, 1.0f, FALLOFF_LINEAR);
  prism_glow_draw(fb2, 32, 32, &prism, 1.0f, 1.0f, 1.0f, 8.0f, 1.0f, FALLOFF_LINEAR);

  // Wider glow should affect more pixels
  int count1 = 0, count2 = 0;
  for (int i = 0; i < 32 * 32 * 4; i += 4) {
    if (fb1[i] > 0.001f)
      count1++;
    if (fb2[i] > 0.001f)
      count2++;
  }
  ASSERT_TRUE(count2 > count1);
  TEST_END();
}

void test_glow_draw_falloff_types(void) {
  TEST_BEGIN("glow_draw_falloff_types");
  float fb_linear[32 * 32 * 4];
  float fb_quad[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++) {
    fb_linear[i] = 0.0f;
    fb_quad[i] = 0.0f;
  }

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  prism_glow_draw(fb_linear, 32, 32, &prism, 1.0f, 1.0f, 1.0f, 5.0f, 1.0f, FALLOFF_LINEAR);
  prism_glow_draw(fb_quad, 32, 32, &prism, 1.0f, 1.0f, 1.0f, 5.0f, 1.0f, FALLOFF_QUADRATIC);

  // Different falloffs should produce different results
  int diff_count = 0;
  for (int i = 0; i < 32 * 32 * 4; i++) {
    if (fabsf(fb_linear[i] - fb_quad[i]) > 0.001f)
      diff_count++;
  }
  ASSERT_TRUE(diff_count > 0);
  TEST_END();
}

void test_glow_outside_prism(void) {
  TEST_BEGIN("glow_outside_prism");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(16.0f, 16.0f, 5.0f, 60.0f, &prism); // Small prism

  prism_glow_draw(fb, 32, 32, &prism, 1.0f, 0.0f, 0.0f, 3.0f, 1.0f, FALLOFF_LINEAR);

  // Corner pixels should not be affected (outside prism)
  int corner_idx = 0; // (0, 0)
  ASSERT_NEAR(fb[corner_idx], 0.0f, 0.001f);

  corner_idx = (31 * 32 + 31) * 4; // (31, 31)
  ASSERT_NEAR(fb[corner_idx], 0.0f, 0.001f);
  TEST_END();
}

// =================================================================================================
// Layer Interface Tests
// =================================================================================================

void test_layer_render_null_config(void) {
  TEST_BEGIN("layer_render_null_config");
  float fb[16 * 16 * 4];
  for (int i = 0; i < 16 * 16 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(8.0f, 8.0f, 5.0f, 60.0f, &prism);

  RenderContext ctx = {
      .fb = fb,
      .width = 16,
      .height = 16,
      .cx = 8.0f,
      .cy = 8.0f,
      .radius = 8.0f,
      .prism = &prism,
      .glow_config = nullptr // No config
  };

  // Should not crash with null config
  layer_prism_glow_render(&ctx);

  // Should not have written anything
  float sum = 0;
  for (int i = 0; i < 16 * 16 * 4; i++)
    sum += fb[i];
  ASSERT_NEAR(sum, 0.0f, 0.001f);
  TEST_END();
}

void test_layer_render_with_config(void) {
  TEST_BEGIN("layer_render_with_config");
  float fb[32 * 32 * 4];
  for (int i = 0; i < 32 * 32 * 4; i++)
    fb[i] = 0.0f;

  Prism prism;
  prism_create(16.0f, 16.0f, 10.0f, 60.0f, &prism);

  GlowConfig glow = {.r = 128,
                     .g = 64,
                     .b = 255,
                     .width = 0.25f, // 25% of radius
                     .intensity = 0.8f,
                     .falloff = FALLOFF_QUADRATIC};

  RenderContext ctx = {.fb = fb,
                       .width = 32,
                       .height = 32,
                       .cx = 16.0f,
                       .cy = 16.0f,
                       .radius = 16.0f,
                       .prism = &prism,
                       .glow_config = &glow};

  layer_prism_glow_render(&ctx);

  // Should have written some pixels
  int nonzero = 0;
  for (int i = 0; i < 32 * 32 * 4; i++) {
    if (fb[i] > 0.0f)
      nonzero++;
  }
  ASSERT_TRUE(nonzero > 0);
  TEST_END();
}

void test_layer_descriptor(void) {
  TEST_BEGIN("layer_descriptor");
  ASSERT_TRUE(LAYER_PRISM_GLOW.name != nullptr);
  ASSERT_TRUE(LAYER_PRISM_GLOW.render != nullptr);
  ASSERT_TRUE(LAYER_PRISM_GLOW.render == layer_prism_glow_render);
  TEST_END();
}

// =================================================================================================
// Test Runner
// =================================================================================================

int main(void) {
  printf("Prism Glow Layer Tests\n");
  printf("======================\n");

  // Smooth minimum tests
  test_smooth_min_equal_values();
  test_smooth_min_far_apart();
  test_smooth_min_close_values();
  test_smooth_min_commutative();
  test_smooth_min_zero_k();

  // Edge distance tests
  test_edge_distance_at_center();
  test_edge_distance_near_edge();
  test_edge_distance_positive();

  // Glow drawing tests
  test_glow_draw_no_crash();
  test_glow_draw_writes_pixels();
  test_glow_draw_additive();
  test_glow_draw_intensity();
  test_glow_draw_glow_width();
  test_glow_draw_falloff_types();
  test_glow_outside_prism();

  // Layer interface tests
  test_layer_render_null_config();
  test_layer_render_with_config();
  test_layer_descriptor();

  TEST_RUNNER_END();
}
