// Test harness for intersection geometry module

#include <stdio.h>

#include "fastmath.h"
#include "geometry/intersect.h"
#include "geometry/prism.h"
#include "geometry/types.h"
#include "test_harness.h"

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Ray-Segment Intersection
// =================================================================================================

void test_ray_segment_hit_middle(void) {
  TEST_BEGIN("ray_segment_hit_middle");

  // Ray from (0, 5) going right, segment from (10, 0) to (10, 10)
  RayHit hit =
      ray_segment_intersect(0.0f, 5.0f, 1.0f, 0.0f, 10.0f, 0.0f, 10.0f, 10.0f, 0.001f, 0.00001f);

  ASSERT_TRUE(hit.hit);
  ASSERT_NEAR(hit.px, 10.0f, 0.001f);
  ASSERT_NEAR(hit.py, 5.0f, 0.001f);
  ASSERT_NEAR(hit.t, 10.0f, 0.001f);
  ASSERT_NEAR(hit.u, 0.5f, 0.001f);

  TEST_END();
}

void test_ray_segment_hit_endpoint(void) {
  TEST_BEGIN("ray_segment_hit_endpoint");

  // Ray hitting near start of segment
  RayHit hit =
      ray_segment_intersect(0.0f, 0.0f, 1.0f, 0.0f, 10.0f, 0.0f, 10.0f, 10.0f, 0.001f, 0.00001f);

  ASSERT_TRUE(hit.hit);
  ASSERT_NEAR(hit.u, 0.0f, 0.001f);

  TEST_END();
}

void test_ray_segment_miss_parallel(void) {
  TEST_BEGIN("ray_segment_miss_parallel");

  // Ray parallel to segment
  RayHit hit =
      ray_segment_intersect(0.0f, 5.0f, 0.0f, 1.0f, 10.0f, 0.0f, 10.0f, 10.0f, 0.001f, 0.00001f);

  ASSERT_FALSE(hit.hit);

  TEST_END();
}

void test_ray_segment_miss_behind(void) {
  TEST_BEGIN("ray_segment_miss_behind");

  // Ray going away from segment
  RayHit hit =
      ray_segment_intersect(20.0f, 5.0f, 1.0f, 0.0f, 10.0f, 0.0f, 10.0f, 10.0f, 0.001f, 0.00001f);

  ASSERT_FALSE(hit.hit);

  TEST_END();
}

void test_ray_segment_miss_outside(void) {
  TEST_BEGIN("ray_segment_miss_outside");

  // Ray misses segment entirely (above it)
  RayHit hit =
      ray_segment_intersect(0.0f, 15.0f, 1.0f, 0.0f, 10.0f, 0.0f, 10.0f, 10.0f, 0.001f, 0.00001f);

  ASSERT_FALSE(hit.hit);

  TEST_END();
}

// =================================================================================================
// Test: Ray-Prism Intersection
// =================================================================================================

void test_prism_find_entry_from_left(void) {
  TEST_BEGIN("prism_find_entry_from_left");

  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Ray from left going right toward center
  RayHit hit = prism_find_entry(100.0f, 200.0f, 1.0f, 0.0f, &p);

  ASSERT_TRUE(hit.hit);
  ASSERT_TRUE(hit.t > 0.0f);
  ASSERT_TRUE(hit.edge_idx >= 0 && hit.edge_idx <= 2);

  TEST_END();
}

void test_prism_find_entry_miss(void) {
  TEST_BEGIN("prism_find_entry_miss");

  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Ray going away from prism
  RayHit hit = prism_find_entry(100.0f, 100.0f, -1.0f, 0.0f, &p);

  ASSERT_FALSE(hit.hit);

  TEST_END();
}

void test_prism_find_exit_from_center(void) {
  TEST_BEGIN("prism_find_exit_from_center");

  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Ray from center going right (angle = 0)
  RayHit hit = prism_find_exit_from_center(200.0f, 200.0f, 0.0f, &p);

  ASSERT_TRUE(hit.hit);
  ASSERT_TRUE(hit.t > 0.0f);
  ASSERT_TRUE(hit.px > 200.0f); // Should exit to the right

  TEST_END();
}

void test_prism_find_exit_downward(void) {
  TEST_BEGIN("prism_find_exit_downward");

  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Ray from center going down (angle = PI/2)
  RayHit hit = prism_find_exit_from_center(200.0f, 200.0f, PI / 2.0f, &p);

  ASSERT_TRUE(hit.hit);
  ASSERT_TRUE(hit.py > 200.0f); // Should exit below center

  TEST_END();
}

// =================================================================================================
// Test: Ray-Circle Intersection
// =================================================================================================

void test_ray_circle_hit_through_center(void) {
  TEST_BEGIN("ray_circle_hit_through_center");

  float out_x, out_y;
  int hit = ray_circle_intersect(0.0f, 0.0f, 1.0f, 0.0f, 100.0f, 0.0f, 50.0f, &out_x, &out_y);

  ASSERT_TRUE(hit);
  ASSERT_NEAR(out_x, 50.0f, 0.1f); // First hit at x=50
  ASSERT_NEAR(out_y, 0.0f, 0.1f);

  TEST_END();
}

void test_ray_circle_hit_tangent(void) {
  TEST_BEGIN("ray_circle_hit_tangent");

  float out_x, out_y;
  // Ray tangent to circle at (100, 50) - center (100, 0), radius 50
  int hit = ray_circle_intersect(0.0f, 50.0f, 1.0f, 0.0f, 100.0f, 0.0f, 50.0f, &out_x, &out_y);

  ASSERT_TRUE(hit);
  ASSERT_NEAR(out_x, 100.0f, 0.5f);
  ASSERT_NEAR(out_y, 50.0f, 0.5f);

  TEST_END();
}

void test_ray_circle_miss(void) {
  TEST_BEGIN("ray_circle_miss");

  float out_x, out_y;
  // Ray above circle
  int hit = ray_circle_intersect(0.0f, 100.0f, 1.0f, 0.0f, 100.0f, 0.0f, 50.0f, &out_x, &out_y);

  ASSERT_FALSE(hit);

  TEST_END();
}

void test_ray_circle_from_inside(void) {
  TEST_BEGIN("ray_circle_from_inside");

  float out_x, out_y;
  // Ray from inside circle
  int hit = ray_circle_intersect(100.0f, 0.0f, 1.0f, 0.0f, 100.0f, 0.0f, 50.0f, &out_x, &out_y);

  ASSERT_TRUE(hit);
  ASSERT_NEAR(out_x, 150.0f, 0.1f); // Should exit at far side

  TEST_END();
}

// =================================================================================================
// Test: Segment-Circle Clipping
// =================================================================================================

void test_clip_segment_both_inside(void) {
  TEST_BEGIN("clip_segment_both_inside");

  float ox0, oy0, ox1, oy1;
  // Segment entirely inside circle
  int clipped = clip_segment_to_circle(100.0f, 100.0f, 110.0f, 110.0f, 100.0f, 100.0f, 50.0f, &ox0,
                                       &oy0, &ox1, &oy1);

  ASSERT_TRUE(clipped);
  ASSERT_NEAR(ox0, 100.0f, 0.01f);
  ASSERT_NEAR(oy0, 100.0f, 0.01f);
  ASSERT_NEAR(ox1, 110.0f, 0.01f);
  ASSERT_NEAR(oy1, 110.0f, 0.01f);

  TEST_END();
}

void test_clip_segment_both_outside(void) {
  TEST_BEGIN("clip_segment_both_outside");

  float ox0, oy0, ox1, oy1;
  // Segment entirely outside and not crossing circle
  int clipped = clip_segment_to_circle(200.0f, 200.0f, 210.0f, 210.0f, 100.0f, 100.0f, 50.0f, &ox0,
                                       &oy0, &ox1, &oy1);

  ASSERT_FALSE(clipped);

  TEST_END();
}

void test_clip_segment_crosses_circle(void) {
  TEST_BEGIN("clip_segment_crosses_circle");

  float ox0, oy0, ox1, oy1;
  // Segment crosses through circle (both ends outside)
  int clipped = clip_segment_to_circle(0.0f, 100.0f, 200.0f, 100.0f, 100.0f, 100.0f, 50.0f, &ox0,
                                       &oy0, &ox1, &oy1);

  ASSERT_TRUE(clipped);
  ASSERT_NEAR(ox0, 50.0f, 1.0f);
  ASSERT_NEAR(ox1, 150.0f, 1.0f);

  TEST_END();
}

void test_clip_segment_one_inside(void) {
  TEST_BEGIN("clip_segment_one_inside");

  float ox0, oy0, ox1, oy1;
  // Start inside, end outside
  int clipped = clip_segment_to_circle(100.0f, 100.0f, 200.0f, 100.0f, 100.0f, 100.0f, 50.0f, &ox0,
                                       &oy0, &ox1, &oy1);

  ASSERT_TRUE(clipped);
  ASSERT_NEAR(ox0, 100.0f, 0.01f); // Start unchanged
  ASSERT_NEAR(ox1, 150.0f, 1.0f);  // End clipped to circle

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Intersection geometry tests\n");
  printf("===========================\n");

  // Ray-segment tests
  test_ray_segment_hit_middle();
  test_ray_segment_hit_endpoint();
  test_ray_segment_miss_parallel();
  test_ray_segment_miss_behind();
  test_ray_segment_miss_outside();

  // Ray-prism tests
  test_prism_find_entry_from_left();
  test_prism_find_entry_miss();
  test_prism_find_exit_from_center();
  test_prism_find_exit_downward();

  // Ray-circle tests
  test_ray_circle_hit_through_center();
  test_ray_circle_hit_tangent();
  test_ray_circle_miss();
  test_ray_circle_from_inside();

  // Segment-circle clipping tests
  test_clip_segment_both_inside();
  test_clip_segment_both_outside();
  test_clip_segment_crosses_circle();
  test_clip_segment_one_inside();

  TEST_RUNNER_END();
}
