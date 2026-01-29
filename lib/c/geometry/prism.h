#pragma once

// =================================================================================================
// Prism Geometry Module
// =================================================================================================
// Functions for creating and querying prism (triangle) geometry.
// The Prism struct is defined in types.h.

#include "geometry/types.h"

// -------------------------------------------------------------------------------------------------
// Prism Creation
// -------------------------------------------------------------------------------------------------

// Create an isosceles triangle prism with apex at top, centered at (cx, cy).
// apex_angle_deg: angle at the apex (top vertex), clamped to [1, 179] degrees
// size: width of the base
void prism_create(float cx, float cy, float size, float apex_angle_deg, Prism *out);

// -------------------------------------------------------------------------------------------------
// Prism Queries
// -------------------------------------------------------------------------------------------------

// Compute characteristic length of prism (average edge length).
// Used for scale-aware epsilon calculations.
float prism_scale(const Prism *prism);

// Get vertex coordinates by index (0, 1, 2).
// v0 = apex (top), v1 = bottom-right, v2 = bottom-left
void prism_get_vertex(const Prism *prism, int idx, float *out_x, float *out_y);

// Get edge endpoints by index (0, 1, 2).
// Edge 0: v0 -> v1, Edge 1: v1 -> v2, Edge 2: v2 -> v0
void prism_get_edge(const Prism *prism, int edge_idx, float *out_ax, float *out_ay, float *out_bx,
                    float *out_by);

// -------------------------------------------------------------------------------------------------
// Point-in-Triangle Test
// -------------------------------------------------------------------------------------------------

// Check if point (px, py) is inside the prism triangle.
// Returns 1 if inside, 0 if outside.
int prism_contains_point(const Prism *prism, float px, float py);

// Generic point-in-triangle test using barycentric coordinates.
// Returns 1 if inside, 0 if outside.
int point_in_triangle(float px, float py, float x0, float y0, float x1, float y1, float x2,
                      float y2);
