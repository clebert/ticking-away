// Test harness for prism bounce detection

#include <stdbool.h>
#include <stdio.h>

// Include real project headers (order matters due to dependencies)
#include "bounce.h"
#include "math.h"
#include "prism.h"

// Test case definitions
#include "bounce_test_cases.h"

// Constants from wasm.c
#define ANGLE_0 (-PI / 2.0f)
#define HOUR_ARC (TAU / 12.0f)

// Shared prism setup
#define CANVAS_SIZE 400
#define PRISM_SIZE_PERCENT 50.0f
#define APEX_ANGLE_DEG 60.0f

// Classification names for output
static const char *location_name(int loc) {
  switch (loc) {
  case 0:
    return "face_0 (right)";
  case 1:
    return "face_1 (bottom)";
  case 2:
    return "face_2 (left)";
  case 3:
    return "vertex_v0 (top)";
  case 4:
    return "vertex_v1 (bottom-right)";
  case 5:
    return "vertex_v2 (bottom-left)";
  default:
    return "INVALID";
  }
}

static const char *vertex_name(int idx) {
  switch (idx) {
  case 0:
    return "v0 (top)";
  case 1:
    return "v1 (bottom-right)";
  case 2:
    return "v2 (bottom-left)";
  default:
    return "none";
  }
}

// Initialize prism with standard parameters
static void init_prism(Prism *prism, float *cx, float *cy, float *radius) {
  *cx = (float)CANVAS_SIZE / 2.0f;
  *cy = (float)CANVAS_SIZE / 2.0f;
  *radius = (float)CANVAS_SIZE / 2.0f - 1.0f;
  float prism_size = (PRISM_SIZE_PERCENT / 100.0f) * (*radius);
  create_prism(*cx, *cy, prism_size, APEX_ANGLE_DEG, prism);
}

// Run a single test case (hour is embedded in test case), returns true if passed
static bool run_test(const TestCase *tc) {
  Prism prism;
  float cx, cy, radius;
  init_prism(&prism, &cx, &cy, &radius);

  float minute_angle = ANGLE_0 + (tc->minute / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  float hour12 = (float)(tc->hour % 12);
  float hour_angle = ANGLE_0 + (hour12 / 12.0f) * TAU + (tc->minute / 60.0f) * HOUR_ARC;

  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  RayHit entry_hit = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, &prism);

  BounceInfo bounce =
      compute_bounce_info(entry_hit.edge_idx, entry_hit.u, hour_angle, &prism, 0);

  return bounce.needs_bounce == tc->expect_bounce;
}

// Print detailed failure info for a test case
static void print_failure(const TestCase *tc) {
  Prism prism;
  float cx, cy, radius;
  init_prism(&prism, &cx, &cy, &radius);

  float minute_angle = ANGLE_0 + (tc->minute / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  float hour12 = (float)(tc->hour % 12);
  float hour_angle = ANGLE_0 + (hour12 / 12.0f) * TAU + (tc->minute / 60.0f) * HOUR_ARC;

  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  RayHit entry_hit = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, &prism);
  RayHit exit_hit = find_prism_exit_from_center(cx, cy, hour_angle, &prism);

  BounceInfo bounce =
      compute_bounce_info(entry_hit.edge_idx, entry_hit.u, hour_angle, &prism, 0);

  int entry_loc = classify_edge_position(entry_hit.edge_idx, entry_hit.u);
  int exit_loc = classify_edge_position(exit_hit.edge_idx, exit_hit.u);

  printf("FAIL: %02d:%05.2f\n", tc->hour, tc->minute);
  printf("  Expected: %s, Got: %s\n", tc->expect_bounce ? "BOUNCE" : "NO_BOUNCE",
         bounce.needs_bounce ? "BOUNCE" : "NO_BOUNCE");
  printf("  Entry: edge=%d u=%.4f (%s)\n", entry_hit.edge_idx, entry_hit.u,
         location_name(entry_loc));
  printf("  Exit:  edge=%d u=%.4f (%s)\n", exit_hit.edge_idx, exit_hit.u, location_name(exit_loc));
  if (bounce.needs_bounce) {
    printf("  Bounce vertex: %s at (%.2f, %.2f)\n", vertex_name(bounce.bounce_vertex_idx),
           bounce.bounce_x, bounce.bounce_y);
  }
  printf("\n");
}

int main(void) {
  int passed = 0;
  int failed = 0;
  int total = 0;

  for (int i = 0; i < (int)TEST_COUNT; i++) {
    total++;
    if (run_test(&test_cases[i])) {
      passed++;
    } else {
      if (failed == 0) {
        printf("=========================================="
               "========================================\n");
        printf("FAILURES:\n");
        printf("=========================================="
               "========================================\n\n");
      }
      print_failure(&test_cases[i]);
      failed++;
    }
  }

  printf("================================================================================\n");
  printf("SUMMARY: %d/%d tests passed", passed, total);
  if (failed > 0) {
    printf(", %d failed\n", failed);
  } else {
    printf("\n");
  }
  printf("================================================================================\n");
  return failed > 0 ? 1 : 0;
}
