#pragma once

// =================================================================================================
// Ray and Segment Intersection Module
// =================================================================================================
// Functions for ray-segment, ray-circle, and segment-circle intersection tests.
// The RayHit struct is defined in types.h.

#include "geometry/types.h"

// -------------------------------------------------------------------------------------------------
// Ray-Segment Intersection
// -------------------------------------------------------------------------------------------------

// Intersect ray (ox, oy) + t*(dx, dy) with line segment (ax, ay)-(bx, by).
// Returns hit info if intersection found with t > eps_t.
// eps_t: tolerance for ray parameter (world units)
// eps_u: tolerance for segment parameter (typically 1e-5f for robustness)
RayHit ray_segment_intersect(float ox, float oy, float dx, float dy, float ax, float ay, float bx,
                             float by, float eps_t, float eps_u);

// -------------------------------------------------------------------------------------------------
// Ray-Prism Intersection
// -------------------------------------------------------------------------------------------------

// Find where a ray from (ox, oy) in direction (dx, dy) first enters the prism.
// Returns hit info with the entry point, edge index, and parametric position along edge.
RayHit prism_find_entry(float ox, float oy, float dx, float dy, const Prism *prism);

// Find where a ray from prism center in direction (angle radians) exits the prism.
// This is used for exit rays that appear to originate from center.
// Takes the farthest hit for stability in degenerate cases.
RayHit prism_find_exit_from_center(float cx, float cy, float angle, const Prism *prism);

// -------------------------------------------------------------------------------------------------
// Ray-Circle Intersection
// -------------------------------------------------------------------------------------------------

// Find intersection of ray with circle. Returns 1 if hit, 0 if miss.
// Ray starts at (ox, oy) with direction (dx, dy) (not necessarily normalized).
// Circle centered at (cx, cy) with given radius.
// Output: intersection point stored in out_x, out_y.
int ray_circle_intersect(float ox, float oy, float dx, float dy, float cx, float cy, float radius,
                         float *out_x, float *out_y);

// -------------------------------------------------------------------------------------------------
// Segment-Circle Clipping
// -------------------------------------------------------------------------------------------------

// Clip a line segment to the interior of a circle.
// Returns 1 if any portion of the segment is inside, 0 if entirely outside.
// Output: clipped segment endpoints stored in out_x0, out_y0, out_x1, out_y1.
int clip_segment_to_circle(float x0, float y0, float x1, float y1, float cx, float cy, float radius,
                           float *out_x0, float *out_y0, float *out_x1, float *out_y1);
