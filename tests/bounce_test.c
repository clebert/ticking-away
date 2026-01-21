// Test harness for prism bounce detection

#include <stdbool.h>
#include <stdio.h>

// Include real project headers (order matters due to dependencies)
#include "bounce.h"
#include "math.h"
#include "prism.h"

// Constants from wasm.c
#define ANGLE_0 (-PI / 2.0f)
#define HOUR_ARC (TAU / 12.0f)

// Test case definition
typedef struct {
  int hour;
  int minute;
  float threshold;
  bool expect_bounce;
  const char *description;
} TestCase;

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

// Run a single test case, returns true if passed
// Matches wasm.c and ray_paths.h exactly
static bool run_test(const TestCase *tc) {
  const int width = 400;
  const int height = 400;
  const float prism_size_percent = 50.0f;
  const float apex_angle_deg = 60.0f;

  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (width < height ? (float)width : (float)height) / 2.0f - 1.0f;

  float prism_size = (prism_size_percent / 100.0f) * radius;
  Prism prism;
  create_prism(cx, cy, prism_size, apex_angle_deg, &prism);

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
      compute_bounce_info(entry_hit.edge_idx, entry_hit.u, hour_angle, &prism, tc->threshold);

  return bounce.needs_bounce == tc->expect_bounce;
}

// Print detailed failure info for a test case
static void print_failure(const TestCase *tc) {
  const int width = 400;
  const int height = 400;
  const float prism_size_percent = 50.0f;
  const float apex_angle_deg = 60.0f;

  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (width < height ? (float)width : (float)height) / 2.0f - 1.0f;

  float prism_size = (prism_size_percent / 100.0f) * radius;
  Prism prism;
  create_prism(cx, cy, prism_size, apex_angle_deg, &prism);

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
      compute_bounce_info(entry_hit.edge_idx, entry_hit.u, hour_angle, &prism, tc->threshold);

  int entry_loc = classify_edge_position(entry_hit.edge_idx, entry_hit.u);
  int exit_loc = classify_edge_position(exit_hit.edge_idx, exit_hit.u);

  printf("FAIL: %02d:%02d (threshold=%.2f) - %s\n", tc->hour, tc->minute, tc->threshold,
         tc->description);
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
  // Define test cases
  // clang-format off
  TestCase tests[] = {
    // Time   Thresh  Expect   Description
    {7,  19, 0.75f, true,  "Entry near v1, exit in middle of face 1"},
    {11,  1, 0.75f, true,  "Entry near v0, exit in middle of face 2"},
    {7,  41, 0.75f, false, "Entry near v2, exit also near v2 (same corner)"},
    // {3,  57, 0.75f, false, "Diagonal path v0->v1 (exit near opposite corner)"},
    {0,  21, 0.75f, true,  "Entry near v1, exit near v0 (needs bounce)"},
    {0,  22, 0.75f, true,  "Entry near v1, exit near v0 (needs bounce)"},
    {0,  23, 0.75f, true,  "Entry near v1, exit near v0 (needs bounce)"},
    {0,  24, 0.75f, false, "Path has sufficient angle for good dispersion"},
  };
  // clang-format on

  int num_tests = sizeof(tests) / sizeof(tests[0]);
  int passed = 0;
  int failed = 0;

  for (int i = 0; i < num_tests; i++) {
    if (run_test(&tests[i])) {
      passed++;
    } else {
      if (failed == 0) {
        printf(
            "================================================================================\n");
        printf("FAILURES:\n");
        printf(
            "================================================================================\n\n");
      }
      print_failure(&tests[i]);
      failed++;
    }
  }

  printf("================================================================================\n");
  printf("SUMMARY: %d/%d tests passed", passed, num_tests);
  if (failed > 0) {
    printf(", %d failed\n", failed);
    printf("================================================================================\n");
    return 1;
  } else {
    printf("\n");
    printf("================================================================================\n");
    return 0;
  }
}
