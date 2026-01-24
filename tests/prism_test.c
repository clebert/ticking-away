// Test harness for prism geometry module

#include "geometry/prism.h"
#include "test_harness.h"
#include <stdio.h>

TEST_RUNNER_BEGIN();

// =================================================================================================
// Test: Prism Creation
// =================================================================================================

void test_prism_create_basic(void) {
  TEST_BEGIN("prism_create_basic");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Check that apex is above base (y increases downward in screen coords)
  float ax, ay, bx, by;
  prism_get_vertex(&p, 0, &ax, &ay); // apex
  prism_get_vertex(&p, 1, &bx, &by); // bottom-right

  // Apex should have smaller y (higher on screen)
  ASSERT_TRUE(ay < by);

  // Bottom vertices should have same y
  float cx, cy;
  prism_get_vertex(&p, 2, &cx, &cy); // bottom-left
  ASSERT_NEAR(by, cy, 0.001f);

  TEST_END();
}

void test_prism_create_centered(void) {
  TEST_BEGIN("prism_create_centered");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Center of prism should be at (200, 200)
  // Centroid = average of vertices
  float ax, ay, bx, by, cx, cy;
  prism_get_vertex(&p, 0, &ax, &ay);
  prism_get_vertex(&p, 1, &bx, &by);
  prism_get_vertex(&p, 2, &cx, &cy);

  float centroid_x = (ax + bx + cx) / 3.0f;
  float centroid_y = (ay + by + cy) / 3.0f;

  ASSERT_NEAR(centroid_x, 200.0f, 0.1f);
  ASSERT_NEAR(centroid_y, 200.0f, 0.1f);

  TEST_END();
}

void test_prism_create_width(void) {
  TEST_BEGIN("prism_create_width");
  Prism p;
  float size = 100.0f;
  prism_create(200.0f, 200.0f, size, 60.0f, &p);

  // Base width should equal size
  float bx, by, cx, cy;
  prism_get_vertex(&p, 1, &bx, &by);
  prism_get_vertex(&p, 2, &cx, &cy);

  float base_width = bx - cx; // right - left
  ASSERT_NEAR(base_width, size, 0.01f);

  TEST_END();
}

void test_prism_create_clamps_angle(void) {
  TEST_BEGIN("prism_create_clamps_angle");

  // Very small angle (should clamp to 1)
  Prism p1;
  prism_create(200.0f, 200.0f, 100.0f, 0.1f, &p1);
  float scale1 = prism_scale(&p1);
  ASSERT_TRUE(scale1 > 0.0f); // Should produce valid prism

  // Very large angle (should clamp to 179)
  Prism p2;
  prism_create(200.0f, 200.0f, 100.0f, 200.0f, &p2);
  float scale2 = prism_scale(&p2);
  ASSERT_TRUE(scale2 > 0.0f); // Should produce valid prism

  TEST_END();
}

// =================================================================================================
// Test: Prism Scale
// =================================================================================================

void test_prism_scale_positive(void) {
  TEST_BEGIN("prism_scale_positive");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  float scale = prism_scale(&p);
  ASSERT_TRUE(scale > 0.0f);

  TEST_END();
}

void test_prism_scale_proportional(void) {
  TEST_BEGIN("prism_scale_proportional");

  // Larger prism should have larger scale
  Prism small, large;
  prism_create(200.0f, 200.0f, 50.0f, 60.0f, &small);
  prism_create(200.0f, 200.0f, 200.0f, 60.0f, &large);

  float scale_small = prism_scale(&small);
  float scale_large = prism_scale(&large);

  ASSERT_TRUE(scale_large > scale_small);
  // Should scale roughly linearly with size
  ASSERT_NEAR(scale_large / scale_small, 4.0f, 0.5f);

  TEST_END();
}

// =================================================================================================
// Test: Prism Vertex/Edge Access
// =================================================================================================

void test_prism_get_vertex_valid(void) {
  TEST_BEGIN("prism_get_vertex_valid");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  float x, y;

  // All vertices should be retrievable
  prism_get_vertex(&p, 0, &x, &y);
  ASSERT_NEAR(x, 200.0f, 0.01f); // apex x centered

  prism_get_vertex(&p, 1, &x, &y);
  ASSERT_TRUE(x > 200.0f); // bottom-right

  prism_get_vertex(&p, 2, &x, &y);
  ASSERT_TRUE(x < 200.0f); // bottom-left

  TEST_END();
}

void test_prism_get_vertex_invalid(void) {
  TEST_BEGIN("prism_get_vertex_invalid");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  float x, y;

  // Invalid indices should return 0
  prism_get_vertex(&p, -1, &x, &y);
  ASSERT_NEAR(x, 0.0f, 0.001f);
  ASSERT_NEAR(y, 0.0f, 0.001f);

  prism_get_vertex(&p, 3, &x, &y);
  ASSERT_NEAR(x, 0.0f, 0.001f);
  ASSERT_NEAR(y, 0.0f, 0.001f);

  TEST_END();
}

void test_prism_get_edge(void) {
  TEST_BEGIN("prism_get_edge");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  float ax, ay, bx, by;
  float v0x, v0y, v1x, v1y;

  // Edge 0 should go from v0 to v1
  prism_get_edge(&p, 0, &ax, &ay, &bx, &by);
  prism_get_vertex(&p, 0, &v0x, &v0y);
  prism_get_vertex(&p, 1, &v1x, &v1y);

  ASSERT_NEAR(ax, v0x, 0.001f);
  ASSERT_NEAR(ay, v0y, 0.001f);
  ASSERT_NEAR(bx, v1x, 0.001f);
  ASSERT_NEAR(by, v1y, 0.001f);

  TEST_END();
}

// =================================================================================================
// Test: Point-in-Triangle
// =================================================================================================

void test_point_in_triangle_inside(void) {
  TEST_BEGIN("point_in_triangle_inside");

  // Simple triangle (0,0), (10,0), (5,10)
  int inside = point_in_triangle(5.0f, 5.0f, 0.0f, 0.0f, 10.0f, 0.0f, 5.0f, 10.0f);
  ASSERT_TRUE(inside);

  TEST_END();
}

void test_point_in_triangle_outside(void) {
  TEST_BEGIN("point_in_triangle_outside");

  // Point clearly outside
  int inside = point_in_triangle(20.0f, 20.0f, 0.0f, 0.0f, 10.0f, 0.0f, 5.0f, 10.0f);
  ASSERT_FALSE(inside);

  TEST_END();
}

void test_point_in_triangle_on_edge(void) {
  TEST_BEGIN("point_in_triangle_on_edge");

  // Point on edge (should be considered inside or on boundary)
  // Midpoint of edge (0,0)-(10,0)
  int inside = point_in_triangle(5.0f, 0.0f, 0.0f, 0.0f, 10.0f, 0.0f, 5.0f, 10.0f);
  ASSERT_TRUE(inside);

  TEST_END();
}

void test_point_in_triangle_at_vertex(void) {
  TEST_BEGIN("point_in_triangle_at_vertex");

  // Point at vertex
  int inside = point_in_triangle(0.0f, 0.0f, 0.0f, 0.0f, 10.0f, 0.0f, 5.0f, 10.0f);
  ASSERT_TRUE(inside);

  TEST_END();
}

void test_prism_contains_point_center(void) {
  TEST_BEGIN("prism_contains_point_center");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Center should be inside
  int inside = prism_contains_point(&p, 200.0f, 200.0f);
  ASSERT_TRUE(inside);

  TEST_END();
}

void test_prism_contains_point_outside(void) {
  TEST_BEGIN("prism_contains_point_outside");
  Prism p;
  prism_create(200.0f, 200.0f, 100.0f, 60.0f, &p);

  // Point far outside
  int inside = prism_contains_point(&p, 0.0f, 0.0f);
  ASSERT_FALSE(inside);

  TEST_END();
}

// =================================================================================================
// Main
// =================================================================================================

int main(void) {
  printf("Prism geometry tests\n");
  printf("====================\n\n");

  // Prism creation tests
  test_prism_create_basic();
  test_prism_create_centered();
  test_prism_create_width();
  test_prism_create_clamps_angle();

  // Prism scale tests
  test_prism_scale_positive();
  test_prism_scale_proportional();

  // Vertex/edge access tests
  test_prism_get_vertex_valid();
  test_prism_get_vertex_invalid();
  test_prism_get_edge();

  // Point-in-triangle tests
  test_point_in_triangle_inside();
  test_point_in_triangle_outside();
  test_point_in_triangle_on_edge();
  test_point_in_triangle_at_vertex();
  test_prism_contains_point_center();
  test_prism_contains_point_outside();

  TEST_RUNNER_END();
}
