// Test harness for line drawing module

#include "draw/line.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// Helper: sum all RGB values in framebuffer (measure total light)
static float sum_rgb(const float *fb, int width, int height) {
  float sum = 0.0f;
  int pixels = width * height;
  for (int i = 0; i < pixels; i++) {
    sum += fb[i * 4 + 0]; // R
    sum += fb[i * 4 + 1]; // G
    sum += fb[i * 4 + 2]; // B
  }
  return sum;
}

// Helper: get pixel value at (x, y)
static void get_pixel(const float *fb, int width, int x, int y, float *r, float *g, float *b) {
  int idx = (y * width + x) * 4;
  *r = fb[idx];
  *g = fb[idx + 1];
  *b = fb[idx + 2];
}

// =================================================================================================
// Test: Basic Line Drawing
// =================================================================================================

void test_line_horizontal(void) {
  TEST_BEGIN("line_horizontal");

  float fb[400 * 4] = {0}; // 20x20 image
  int w = 20, h = 20;

  // Draw horizontal line in middle
  line_draw_glow(fb, w, h, 2.0f, 10.0f, 18.0f, 10.0f, 1.0f, 1.0f, 1.0f, // White
                 3.0f,                                                  // glow_width
                 1.0f,                                                  // intensity
                 FALLOFF_LINEAR, nullptr, nullptr, nullptr);

  // Check that pixels near the line have non-zero values
  float r, g, b;
  get_pixel(fb, w, 10, 10, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  // Check pixels far from line are zero
  get_pixel(fb, w, 10, 0, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f);

  TEST_END();
}

void test_line_vertical(void) {
  TEST_BEGIN("line_vertical");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  line_draw_glow(fb, w, h, 10.0f, 2.0f, 10.0f, 18.0f, 0.0f, 1.0f, 0.0f, // Green
                 3.0f, 1.0f, FALLOFF_LINEAR, nullptr, nullptr, nullptr);

  float r, g, b;
  get_pixel(fb, w, 10, 10, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f); // No red
  ASSERT_TRUE(g > 0.0f);        // Has green

  TEST_END();
}

void test_line_diagonal(void) {
  TEST_BEGIN("line_diagonal");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  line_draw_glow(fb, w, h, 2.0f, 2.0f, 18.0f, 18.0f, 1.0f, 0.0f, 0.0f, // Red
                 3.0f, 1.0f, FALLOFF_LINEAR, nullptr, nullptr, nullptr);

  // Check diagonal pixels
  float r, g, b;
  get_pixel(fb, w, 5, 5, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  get_pixel(fb, w, 15, 15, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  // Corner should be unaffected
  get_pixel(fb, w, 0, 19, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Intensity Gradient
// =================================================================================================

void test_line_gradient_intensity(void) {
  TEST_BEGIN("line_gradient_intensity");

  float fb[1000 * 4] = {0}; // 50x20 image
  int w = 50, h = 20;

  // Draw line with gradient: bright at start, dim at end
  line_draw_glow_gradient(fb, w, h, 5.0f, 10.0f, 45.0f, 10.0f, 1.0f, 1.0f, 1.0f, 3.0f,
                          1.0f, // intensity_start
                          0.1f, // intensity_end (much dimmer)
                          FALLOFF_LINEAR, nullptr, nullptr, nullptr);

  // Pixel near start should be brighter than pixel near end
  float r1, g1, b1, r2, g2, b2;
  get_pixel(fb, w, 8, 10, &r1, &g1, &b1);
  get_pixel(fb, w, 42, 10, &r2, &g2, &b2);

  ASSERT_TRUE(r1 > r2);

  TEST_END();
}

// =================================================================================================
// Test: Falloff Types
// =================================================================================================

void test_line_falloff_quadratic(void) {
  TEST_BEGIN("line_falloff_quadratic");

  float fb1[400 * 4] = {0};
  float fb2[400 * 4] = {0};
  int w = 20, h = 20;

  // Same line with different falloffs
  line_draw_glow(fb1, w, h, 5.0f, 10.0f, 15.0f, 10.0f, 1.0f, 1.0f, 1.0f, 5.0f, 1.0f, FALLOFF_LINEAR,
                 nullptr, nullptr, nullptr);

  line_draw_glow(fb2, w, h, 5.0f, 10.0f, 15.0f, 10.0f, 1.0f, 1.0f, 1.0f, 5.0f, 1.0f,
                 FALLOFF_QUADRATIC, nullptr, nullptr, nullptr);

  // Quadratic should fall off faster, so total light should be less
  float sum1 = sum_rgb(fb1, w, h);
  float sum2 = sum_rgb(fb2, w, h);

  ASSERT_TRUE(sum2 < sum1);

  TEST_END();
}

// =================================================================================================
// Test: Circle Clipping
// =================================================================================================

void test_line_clip_circle(void) {
  TEST_BEGIN("line_clip_circle");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  // Circle at center, radius 5
  float circle[3] = {10.0f, 10.0f, 5.0f};

  // Long horizontal line clipped to circle
  line_draw_glow(fb, w, h, 0.0f, 10.0f, 20.0f, 10.0f, 1.0f, 1.0f, 1.0f, 2.0f, 1.0f, FALLOFF_LINEAR,
                 nullptr, circle, nullptr);

  // Pixel inside circle should have value
  float r, g, b;
  get_pixel(fb, w, 10, 10, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  // Pixel outside circle should be zero
  get_pixel(fb, w, 0, 10, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f);

  get_pixel(fb, w, 19, 10, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Triangle Clipping
// =================================================================================================

void test_line_clip_triangle(void) {
  TEST_BEGIN("line_clip_triangle");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  // Triangle in upper-left quadrant
  float tri[6] = {0.0f, 0.0f, 10.0f, 0.0f, 0.0f, 10.0f};

  // Line that crosses both inside and outside triangle
  line_draw_glow(fb, w, h, 0.0f, 5.0f, 20.0f, 5.0f, 1.0f, 1.0f, 1.0f, 2.0f, 1.0f, FALLOFF_LINEAR,
                 tri, nullptr, nullptr);

  // Pixel inside triangle should have value
  float r, g, b;
  get_pixel(fb, w, 2, 5, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  // Pixel outside triangle should be zero
  get_pixel(fb, w, 15, 5, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Triangle Exclusion
// =================================================================================================

void test_line_exclude_triangle(void) {
  TEST_BEGIN("line_exclude_triangle");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  // Triangle to exclude (center of image)
  float exclude[6] = {10.0f, 5.0f, 15.0f, 15.0f, 5.0f, 15.0f};

  // Line through center
  line_draw_glow(fb, w, h, 0.0f, 10.0f, 20.0f, 10.0f, 1.0f, 1.0f, 1.0f, 2.0f, 1.0f, FALLOFF_LINEAR,
                 nullptr, nullptr, exclude);

  // Pixel outside exclusion should have value
  float r, g, b;
  get_pixel(fb, w, 2, 10, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  // Pixel inside exclusion zone should be zero
  get_pixel(fb, w, 10, 10, &r, &g, &b);
  ASSERT_NEAR(r, 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Edge Cases
// =================================================================================================

void test_line_zero_length(void) {
  TEST_BEGIN("line_zero_length");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  // Zero-length line (point)
  line_draw_glow(fb, w, h, 10.0f, 10.0f, 10.0f, 10.0f, 1.0f, 1.0f, 1.0f, 3.0f, 1.0f, FALLOFF_LINEAR,
                 nullptr, nullptr, nullptr);

  // Should create a circular glow around the point
  float r, g, b;
  get_pixel(fb, w, 10, 10, &r, &g, &b);
  ASSERT_TRUE(r > 0.0f);

  TEST_END();
}

void test_line_outside_framebuffer(void) {
  TEST_BEGIN("line_outside_framebuffer");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  // Line completely outside framebuffer
  line_draw_glow(fb, w, h, 100.0f, 100.0f, 200.0f, 100.0f, 1.0f, 1.0f, 1.0f, 3.0f, 1.0f,
                 FALLOFF_LINEAR, nullptr, nullptr, nullptr);

  // Framebuffer should remain zero
  float sum = sum_rgb(fb, w, h);
  ASSERT_NEAR(sum, 0.0f, 0.001f);

  TEST_END();
}

void test_line_zero_intensity(void) {
  TEST_BEGIN("line_zero_intensity");

  float fb[400 * 4] = {0};
  int w = 20, h = 20;

  line_draw_glow(fb, w, h, 5.0f, 10.0f, 15.0f, 10.0f, 1.0f, 1.0f, 1.0f, 3.0f,
                 0.0f, // Zero intensity
                 FALLOFF_LINEAR, nullptr, nullptr, nullptr);

  // No light should be added
  float sum = sum_rgb(fb, w, h);
  ASSERT_NEAR(sum, 0.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Line drawing tests\n");
  printf("==================\n");

  // Basic line drawing
  test_line_horizontal();
  test_line_vertical();
  test_line_diagonal();

  // Intensity gradient
  test_line_gradient_intensity();

  // Falloff types
  test_line_falloff_quadratic();

  // Clipping
  test_line_clip_circle();
  test_line_clip_triangle();
  test_line_exclude_triangle();

  // Edge cases
  test_line_zero_length();
  test_line_outside_framebuffer();
  test_line_zero_intensity();

  TEST_RUNNER_END();
}
