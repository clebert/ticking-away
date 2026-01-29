#pragma once

// =================================================================================================
// Geometry Primitives
// =================================================================================================
// Public type definitions for geometry operations. Used by config and layers.

// -------------------------------------------------------------------------------------------------
// Prism (Triangle)
// -------------------------------------------------------------------------------------------------

typedef struct {
  float vertices[6]; // 3 vertices x 2 coords: [v0.x, v0.y, v1.x, v1.y, v2.x, v2.y]
                     // v0 = apex (top), v1 = bottom-right, v2 = bottom-left
} Prism;

// -------------------------------------------------------------------------------------------------
// Ray Hit Result
// -------------------------------------------------------------------------------------------------

typedef struct {
  int hit;      // 1 if intersection found, 0 otherwise
  float t;      // Parameter along ray (distance from origin in direction units)
  float u;      // Parameter along edge (0=start vertex, 1=end vertex), -1 if not set
  int edge_idx; // Which edge was hit (0, 1, 2 for prism), -1 if not set
  float px, py; // Hit point coordinates
} RayHit;

// -------------------------------------------------------------------------------------------------
// Segment (Precomputed for efficiency)
// -------------------------------------------------------------------------------------------------

typedef struct {
  float x0, y0;     // Start point
  float x1, y1;     // End point
  float dx, dy;     // Direction vector (x1 - x0, y1 - y0)
  float len_sq;     // Squared length
  float inv_len_sq; // 1 / len_sq (0 if degenerate)
  float len;        // sqrt(len_sq), precomputed for capsule intersection
  float inv_len;    // 1 / len, precomputed for capsule intersection
} Segment;
