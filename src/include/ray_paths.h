#pragma once

#include "bounce.h"
#include "geometry.h"
#include "math.h"
#include "prism.h"
#include "rainbow.h"

// =================================================================================================
// Ray Path Geometry
// =================================================================================================
//
// This module computes the geometry of light rays through the prism, decoupled from rendering.
// It provides all coordinates needed to draw the rays, without any visual concerns (colors, glow).
//
// Ray path structure:
//   1. Entry ray: from light source to prism entry point (clipped to circle)
//   2. Internal path: either direct (entry→exit) or bounced (entry→bounce→exit)
//   3. Exit rays: from prism exit to circle boundary (one per color band)

// =================================================================================================
// Constants
// =================================================================================================

#define RAINBOW_SPREAD_EPSILON 0.001f  // Threshold for treating rainbow_spread as zero
#define INTERNAL_SPREAD_SCALE 2.0f     // Multiplier for internal ray fan visual width

// =================================================================================================
// Data Structures
// =================================================================================================

// A line segment with start and end points
typedef struct {
  float x0, y0;  // Start point
  float x1, y1;  // End point
  int valid;     // 1 if segment exists, 0 if not
} RaySegment;

// Path for a single color band through the prism
typedef struct {
  // Internal path segment 1: entry point to either exit or bounce point
  RaySegment internal_seg1;

  // Internal path segment 2: bounce point to exit (only valid if bounced)
  RaySegment internal_seg2;

  // Exit ray: from prism exit to circle boundary
  RaySegment exit_ray;

  // Internal endpoint with fan offset applied
  float internal_exit_x, internal_exit_y;

  // Prism exit point (before fan offset)
  float prism_exit_x, prism_exit_y;

  // Exit angle for this band
  float exit_angle;
} BandPath;

// Complete ray path geometry for the entire scene
typedef struct {
  // Entry ray (shared by all bands): from light source to prism entry
  RaySegment entry_ray;

  // Prism entry point
  float entry_x, entry_y;
  int entry_edge;
  float entry_u;

  // Bounce info (shared by all bands)
  int needs_bounce;
  float bounce_x, bounce_y;

  // Per-band paths
  BandPath bands[NUM_BANDS];

  // Whether the ray hits the prism at all
  int hits_prism;

  // Boundary ray data for gradient rendering
  float angle_first, angle_last;          // Exit angles for first/last bands
  float exit_first_x, exit_first_y;       // Prism exit for first band
  float exit_last_x, exit_last_y;         // Prism exit for last band
  float border_first_x, border_first_y;   // Circle boundary for first band
  float border_last_x, border_last_y;     // Circle boundary for last band
  int gradient_valid;                     // Whether gradient boundary data is valid
} RayPaths;

// =================================================================================================
// Path Computation
// =================================================================================================

// Compute all ray path geometry for the scene.
//
// Parameters:
//   cx, cy: Center of watchface
//   radius: Watchface radius
//   entry_x, entry_y: Light source position (minute hand)
//   hour_angle: Angle to hour position from center
//   rainbow_spread: 0.0 (no spread) to 1.0 (30 degree spread)
//   prism: The prism geometry
//
// Returns:
//   RayPaths struct containing all computed coordinates
static RayPaths compute_ray_paths(
  float cx, float cy, float radius,
  float entry_x, float entry_y,
  float hour_angle,
  float rainbow_spread,
  const Prism* prism
) {
  RayPaths paths = {0};

  // Entry ray direction: toward center
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  // Find where entry ray hits prism
  RayHit prism_entry = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, prism);

  if (!prism_entry.hit) {
    paths.hits_prism = 0;
    return paths;
  }

  paths.hits_prism = 1;
  paths.entry_x = prism_entry.px;
  paths.entry_y = prism_entry.py;
  paths.entry_edge = prism_entry.edge_idx;
  paths.entry_u = prism_entry.u;

  // Clip incoming ray to circle
  float clip_x0, clip_y0, clip_x1, clip_y1;
  int has_clipped_entry = clip_segment_to_circle(
    entry_x, entry_y, prism_entry.px, prism_entry.py,
    cx, cy, radius,
    &clip_x0, &clip_y0, &clip_x1, &clip_y1
  );

  if (has_clipped_entry) {
    paths.entry_ray.x0 = clip_x0;
    paths.entry_ray.y0 = clip_y0;
    paths.entry_ray.x1 = clip_x1;
    paths.entry_ray.y1 = clip_y1;
    paths.entry_ray.valid = 1;
  }

  // Compute bounce decision (shared by all bands)
  BounceInfo bounce = compute_bounce_info(
    prism_entry.edge_idx, prism_entry.u,
    hour_angle,
    prism
  );

  paths.needs_bounce = bounce.needs_bounce;
  paths.bounce_x = bounce.bounce_x;
  paths.bounce_y = bounce.bounce_y;

  // Compute boundary ray data for gradient rendering
  if (rainbow_spread > RAINBOW_SPREAD_EPSILON) {
    paths.angle_first = compute_exit_angle(hour_angle, rainbow_spread, 0);
    paths.angle_last = compute_exit_angle(hour_angle, rainbow_spread, NUM_BANDS - 1);

    RayHit exit_first = find_prism_exit_from_center(cx, cy, paths.angle_first, prism);
    RayHit exit_last = find_prism_exit_from_center(cx, cy, paths.angle_last, prism);

    if (exit_first.hit && exit_last.hit) {
      paths.exit_first_x = exit_first.px;
      paths.exit_first_y = exit_first.py;
      paths.exit_last_x = exit_last.px;
      paths.exit_last_y = exit_last.py;

      // Compute circle boundary intersections
      float ext_dir_first_x = cosf_approx(paths.angle_first);
      float ext_dir_first_y = sinf_approx(paths.angle_first);
      if (ray_circle_intersection(exit_first.px, exit_first.py, ext_dir_first_x, ext_dir_first_y,
                                  cx, cy, radius, &paths.border_first_x, &paths.border_first_y)) {
        float ext_dir_last_x = cosf_approx(paths.angle_last);
        float ext_dir_last_y = sinf_approx(paths.angle_last);
        if (ray_circle_intersection(exit_last.px, exit_last.py, ext_dir_last_x, ext_dir_last_y,
                                    cx, cy, radius, &paths.border_last_x, &paths.border_last_y)) {
          paths.gradient_valid = 1;
        }
      }
    }
  }

  // Compute per-band paths
  for (int i = 0; i < NUM_BANDS; i++) {
    BandPath* band = &paths.bands[i];

    // Compute exit angle for this band
    band->exit_angle = compute_exit_angle(hour_angle, rainbow_spread, i);

    // Find where exit ray exits the prism
    RayHit prism_exit = find_prism_exit_from_center(cx, cy, band->exit_angle, prism);

    if (!prism_exit.hit) {
      continue;
    }

    band->prism_exit_x = prism_exit.px;
    band->prism_exit_y = prism_exit.py;

    // Apply internal fan offset
    float internal_t = (float)i / (float)(NUM_BANDS - 1);
    float internal_spread = rainbow_spread * INTERNAL_FAN_FACTOR * MAX_SPREAD_RAD;
    float internal_offset = (0.5f - internal_t) * internal_spread;

    band->internal_exit_x = prism_exit.px + cosf_approx(band->exit_angle + PI/2) * internal_offset * INTERNAL_SPREAD_SCALE;
    band->internal_exit_y = prism_exit.py + sinf_approx(band->exit_angle + PI/2) * internal_offset * INTERNAL_SPREAD_SCALE;

    // Internal path segments
    if (bounce.needs_bounce) {
      // Segment 1: entry → bounce
      band->internal_seg1.x0 = prism_entry.px;
      band->internal_seg1.y0 = prism_entry.py;
      band->internal_seg1.x1 = bounce.bounce_x;
      band->internal_seg1.y1 = bounce.bounce_y;
      band->internal_seg1.valid = 1;

      // Segment 2: bounce → exit
      band->internal_seg2.x0 = bounce.bounce_x;
      band->internal_seg2.y0 = bounce.bounce_y;
      band->internal_seg2.x1 = band->internal_exit_x;
      band->internal_seg2.y1 = band->internal_exit_y;
      band->internal_seg2.valid = 1;
    } else {
      // Direct path: entry → exit
      band->internal_seg1.x0 = prism_entry.px;
      band->internal_seg1.y0 = prism_entry.py;
      band->internal_seg1.x1 = band->internal_exit_x;
      band->internal_seg1.y1 = band->internal_exit_y;
      band->internal_seg1.valid = 1;
    }

    // Exit ray: from prism exit to circle edge
    // Note: prism exit is inside circle, border is on circle, so no clipping needed
    float exit_dir_x = cosf_approx(band->exit_angle);
    float exit_dir_y = sinf_approx(band->exit_angle);

    float border_x, border_y;
    if (ray_circle_intersection(
      prism_exit.px, prism_exit.py,
      exit_dir_x, exit_dir_y,
      cx, cy, radius,
      &border_x, &border_y
    )) {
      band->exit_ray.x0 = prism_exit.px;
      band->exit_ray.y0 = prism_exit.py;
      band->exit_ray.x1 = border_x;
      band->exit_ray.y1 = border_y;
      band->exit_ray.valid = 1;
    }
  }

  return paths;
}
