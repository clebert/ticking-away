// Test harness for segment geometry module

#include <stdio.h>

#include "geometry/segment.h"
#include "geometry/types.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Segment Initialization
// =================================================================================================

void test_segment_init_basic(void) {
  TEST_BEGIN("segment_init_basic");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 10.0f, 0.0f);

  ASSERT_NEAR(s.x0, 0.0f, 0.001f);
  ASSERT_NEAR(s.y0, 0.0f, 0.001f);
  ASSERT_NEAR(s.x1, 10.0f, 0.001f);
  ASSERT_NEAR(s.y1, 0.0f, 0.001f);
  ASSERT_NEAR(s.dx, 10.0f, 0.001f);
  ASSERT_NEAR(s.dy, 0.0f, 0.001f);
  ASSERT_NEAR(s.len, 10.0f, 0.001f);
  ASSERT_NEAR(s.len_sq, 100.0f, 0.001f);

  TEST_END();
}

void test_segment_init_diagonal(void) {
  TEST_BEGIN("segment_init_diagonal");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 3.0f, 4.0f); // 3-4-5 triangle

  ASSERT_NEAR(s.len, 5.0f, 0.001f);
  ASSERT_NEAR(s.len_sq, 25.0f, 0.001f);
  ASSERT_NEAR(s.inv_len, 0.2f, 0.001f);

  TEST_END();
}

void test_segment_init_degenerate(void) {
  TEST_BEGIN("segment_init_degenerate");
  Segment s;
  segment_init(&s, 5.0f, 5.0f, 5.0f, 5.0f); // Zero-length segment

  ASSERT_NEAR(s.len, 0.0f, 0.001f);
  ASSERT_NEAR(s.len_sq, 0.0f, 0.001f);
  ASSERT_NEAR(s.inv_len, 0.0f, 0.001f); // Should be 0 for degenerate

  TEST_END();
}

// =================================================================================================
// Test: Point-to-Segment Distance
// =================================================================================================

void test_segment_distance_on_segment(void) {
  TEST_BEGIN("segment_distance_on_segment");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 10.0f, 0.0f);

  float dist_sq = segment_point_distance_sq(&s, 5.0f, 0.0f);
  ASSERT_NEAR(dist_sq, 0.0f, 0.001f);

  TEST_END();
}

void test_segment_distance_perpendicular(void) {
  TEST_BEGIN("segment_distance_perpendicular");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 10.0f, 0.0f);

  // Point 3 units above midpoint
  float dist_sq = segment_point_distance_sq(&s, 5.0f, 3.0f);
  ASSERT_NEAR(dist_sq, 9.0f, 0.001f);

  TEST_END();
}

void test_segment_distance_to_endpoint(void) {
  TEST_BEGIN("segment_distance_to_endpoint");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 10.0f, 0.0f);

  // Point beyond start of segment
  float dist_sq = segment_point_distance_sq(&s, -3.0f, 0.0f);
  ASSERT_NEAR(dist_sq, 9.0f, 0.001f); // Distance to (0,0)

  // Point beyond end of segment
  dist_sq = segment_point_distance_sq(&s, 14.0f, 0.0f);
  ASSERT_NEAR(dist_sq, 16.0f, 0.001f); // Distance to (10,0)

  TEST_END();
}

void test_segment_distance_with_t(void) {
  TEST_BEGIN("segment_distance_with_t");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 10.0f, 0.0f);

  float t;
  float dist_sq = segment_point_distance_sq_with_t(&s, 5.0f, 3.0f, &t);

  ASSERT_NEAR(dist_sq, 9.0f, 0.001f);
  ASSERT_NEAR(t, 0.5f, 0.001f); // Midpoint

  TEST_END();
}

void test_segment_distance_t_clamped(void) {
  TEST_BEGIN("segment_distance_t_clamped");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 10.0f, 0.0f);

  float t;

  // Point before segment start
  segment_point_distance_sq_with_t(&s, -5.0f, 0.0f, &t);
  ASSERT_NEAR(t, 0.0f, 0.001f); // Clamped to start

  // Point after segment end
  segment_point_distance_sq_with_t(&s, 15.0f, 0.0f, &t);
  ASSERT_NEAR(t, 1.0f, 0.001f); // Clamped to end

  TEST_END();
}

void test_point_to_segment_distance_standalone(void) {
  TEST_BEGIN("point_to_segment_distance_standalone");

  float dist = point_to_segment_distance(5.0f, 4.0f, 0.0f, 0.0f, 10.0f, 0.0f);
  ASSERT_NEAR(dist, 4.0f, 0.001f);

  TEST_END();
}

void test_segment_distance_degenerate(void) {
  TEST_BEGIN("segment_distance_degenerate");
  Segment s;
  segment_init(&s, 5.0f, 5.0f, 5.0f, 5.0f); // Point segment

  float dist_sq = segment_point_distance_sq(&s, 8.0f, 9.0f);
  // Distance should be to the point (5,5): sqrt((8-5)^2 + (9-5)^2) = sqrt(25) = 5
  ASSERT_NEAR(dist_sq, 25.0f, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Capsule-Scanline Intersection
// =================================================================================================

void test_capsule_scanline_horizontal_line(void) {
  TEST_BEGIN("capsule_scanline_horizontal_line");
  Segment s;
  segment_init(&s, 10.0f, 50.0f, 90.0f, 50.0f); // Horizontal at y=50

  int x_lo, x_hi;

  // Scanline through center
  int hit = capsule_scanline_intersect(50.0f, &s, 10.0f, &x_lo, &x_hi);
  ASSERT_TRUE(hit);
  ASSERT_TRUE(x_lo <= 0);   // Should extend left of segment start - r
  ASSERT_TRUE(x_hi >= 100); // Should extend right of segment end + r

  TEST_END();
}

void test_capsule_scanline_vertical_line(void) {
  TEST_BEGIN("capsule_scanline_vertical_line");
  Segment s;
  segment_init(&s, 50.0f, 10.0f, 50.0f, 90.0f); // Vertical at x=50

  int x_lo, x_hi;

  // Scanline through middle
  int hit = capsule_scanline_intersect(50.0f, &s, 10.0f, &x_lo, &x_hi);
  ASSERT_TRUE(hit);
  ASSERT_TRUE(x_lo <= 40); // 50 - 10
  ASSERT_TRUE(x_hi >= 60); // 50 + 10

  TEST_END();
}

void test_capsule_scanline_diagonal(void) {
  TEST_BEGIN("capsule_scanline_diagonal");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 100.0f, 100.0f); // Diagonal

  int x_lo, x_hi;

  // Scanline at y=50 (midpoint)
  int hit = capsule_scanline_intersect(50.0f, &s, 10.0f, &x_lo, &x_hi);
  ASSERT_TRUE(hit);
  // Should cover around x=50 plus/minus capsule radius
  ASSERT_TRUE(x_lo <= 45);
  ASSERT_TRUE(x_hi >= 55);

  TEST_END();
}

void test_capsule_scanline_miss(void) {
  TEST_BEGIN("capsule_scanline_miss");
  Segment s;
  segment_init(&s, 0.0f, 0.0f, 100.0f, 0.0f); // Horizontal at y=0

  int x_lo, x_hi;

  // Scanline far above capsule
  int hit = capsule_scanline_intersect(100.0f, &s, 10.0f, &x_lo, &x_hi);
  ASSERT_FALSE(hit);

  TEST_END();
}

void test_capsule_scanline_endcap_only(void) {
  TEST_BEGIN("capsule_scanline_endcap_only");
  Segment s;
  segment_init(&s, 50.0f, 50.0f, 150.0f, 50.0f); // Horizontal at y=50

  int x_lo, x_hi;

  // Scanline near the top of the start endcap
  int hit = capsule_scanline_intersect(42.0f, &s, 10.0f, &x_lo, &x_hi);
  ASSERT_TRUE(hit); // Should hit the circular endcaps

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Segment geometry tests\n");
  printf("======================\n\n");

  // Segment initialization tests
  test_segment_init_basic();
  test_segment_init_diagonal();
  test_segment_init_degenerate();

  // Point-to-segment distance tests
  test_segment_distance_on_segment();
  test_segment_distance_perpendicular();
  test_segment_distance_to_endpoint();
  test_segment_distance_with_t();
  test_segment_distance_t_clamped();
  test_point_to_segment_distance_standalone();
  test_segment_distance_degenerate();

  // Capsule-scanline tests
  test_capsule_scanline_horizontal_line();
  test_capsule_scanline_vertical_line();
  test_capsule_scanline_diagonal();
  test_capsule_scanline_miss();
  test_capsule_scanline_endcap_only();

  TEST_RUNNER_END();
}
