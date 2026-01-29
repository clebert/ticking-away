#pragma once

// =================================================================================================
// Segment Operations Module
// =================================================================================================
// Functions for segment initialization, point-to-segment distance, and capsule intersection.
// The Segment struct is defined in types.h.

#include "geometry/types.h"

// -------------------------------------------------------------------------------------------------
// Segment Initialization
// -------------------------------------------------------------------------------------------------

// Initialize a Segment with precomputed values for efficient repeated queries.
// Call once per line segment, then use the result for multiple point queries.
void segment_init(Segment *s, float x0, float y0, float x1, float y1);

// -------------------------------------------------------------------------------------------------
// Point-to-Segment Distance
// -------------------------------------------------------------------------------------------------

// Returns squared distance from point to segment (no sqrt).
// Use when only comparing distances - more efficient than actual distance.
float segment_point_distance_sq(const Segment *s, float px, float py);

// Returns squared distance and also outputs position along segment (0=start, 1=end).
// out_t: parametric position of closest point on segment
float segment_point_distance_sq_with_t(const Segment *s, float px, float py, float *out_t);

// Compute distance from point (px, py) to line segment.
// Standalone version without precomputed Segment - slower but convenient for one-off queries.
float point_to_segment_distance(float px, float py, float x0, float y0, float x1, float y1);

// -------------------------------------------------------------------------------------------------
// Capsule-Scanline Intersection
// -------------------------------------------------------------------------------------------------

// Compute x-interval where capsule intersects a horizontal scanline.
// Returns 0 if no intersection, 1 if intersection found.
// The capsule is defined by precomputed segment params with radius r (glow width).
//
// Algorithm: A capsule is the Minkowski sum of a line segment and a disk.
// We decompose it into three regions:
//   1. Start cap: circle at segment start (x0, y0)
//   2. End cap: circle at segment end (x1, y1)
//   3. Rectangle body: slab of width 2r around the segment
// The final x-interval is the union of all intersecting regions.
int capsule_scanline_intersect(float y, const Segment *seg, float r, int *out_x_lo, int *out_x_hi);
