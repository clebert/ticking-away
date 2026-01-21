#pragma once

#include "math.h"
#include "prism.h"

// =================================================================================================
// Light Ray Bounce Detection
// =================================================================================================
//
// Problem: When the light ray's entry and exit points are on the same prism face, the internal
// path runs along (or parallel to) that edge. This makes the prism interior appear dark because
// no light visibly traverses it.
//
// Solution: Detect these "edge-hugging" cases and route the light through the opposite vertex,
// creating a two-segment path (entry → bounce vertex → exit) that illuminates the interior.
//
// Prism geometry (equilateral triangle, apex up):
//
//                 v0 (12 o'clock, -π/2)
//                 /\
//                /  \
//     Face 2    /    \    Face 0
//     (left)   /      \   (right)
//             /________\
//           v2          v1
//     (8 o'clock)    (4 o'clock)
//       (5π/6)         (π/6)
//
//              Face 1 (bottom)
//
// Face definitions:
//   Face 0 (right):  v0 → v1, covers hour angles from -π/2 to π/6
//   Face 1 (bottom): v1 → v2, covers hour angles from π/6 to 5π/6
//   Face 2 (left):   v2 → v0, covers hour angles from 5π/6 to -π/2 (wrapping)
//
// Bounce rules:
//   - Entry on face F, exit on face F → bounce through vertex (F+2)%3 (opposite vertex)
//   - Entry at vertex V, exit NOT on face (V+1)%3 → bounce through vertex (exit_face+2)%3
//   - Entry at vertex V, exit on face (V+1)%3 → no bounce (path crosses interior naturally)
//
// The "opposite vertex" for face F is the vertex not touching that face:
//   Face 0 (v0-v1) → opposite vertex is v2 (index 2)
//   Face 1 (v1-v2) → opposite vertex is v0 (index 0)
//   Face 2 (v2-v0) → opposite vertex is v1 (index 1)
//
// =================================================================================================

typedef struct {
  int needs_bounce;        // 1 if light should bounce through a vertex, 0 for direct path
  int bounce_vertex_idx;   // Which vertex to bounce through: 0=v0, 1=v1, 2=v2, -1=none
  float bounce_x, bounce_y; // Bounce point coordinates (valid only if needs_bounce=1)
} BounceInfo;

// Classify a hit point on a prism edge as either a face or vertex location.
//
// Parameters:
//   edge_idx: Which edge was hit (0=right v0→v1, 1=bottom v1→v2, 2=left v2→v0)
//   u: Parametric position along edge (0.0=start vertex, 1.0=end vertex)
//
// Returns:
//   0-2: Point is on a face (0=right, 1=bottom, 2=left)
//   3-5: Point is at a vertex (3=v0, 4=v1, 5=v2)
//
// Vertex detection uses a scale-independent threshold: if u < 0.05 or u > 0.95,
// the point is considered to be at the start or end vertex of the edge.
// This 5% threshold provides stability against floating-point variation at 60fps.
static int classify_edge_position(int edge_idx, float u) {
  // Guard against invalid inputs (e.g., from failed ray intersection)
  if (edge_idx < 0 || edge_idx > 2) return -1;

  // Threshold: within 2% of edge length counts as "at vertex".
  // This defines the "vertex zone" for bounce logic decisions.
  // Empirical analysis shows u values like 0.0156 occur near vertices,
  // so 2% correctly classifies these as vertex hits rather than face hits.
  // Values transition smoothly (no frame-to-frame jitter), so the threshold
  // is purely a geometric definition, not a stability margin.
  const float VERTEX_THRESHOLD = 0.02f;

  if (u < VERTEX_THRESHOLD) {
    // At start vertex of edge: edge 0→v0, edge 1→v1, edge 2→v2
    return 3 + edge_idx;
  } else if (u > 1.0f - VERTEX_THRESHOLD) {
    // At end vertex of edge: edge 0→v1, edge 1→v2, edge 2→v0
    return 3 + ((edge_idx + 1) % 3);
  } else {
    // On the face (not at a vertex)
    return edge_idx;
  }
}

// Compute whether a light ray needs to bounce through a vertex to illuminate the prism interior.
//
// Parameters:
//   entry_edge: Which edge the ray entered through (from RayHit.edge_idx)
//   entry_u: Parametric position along entry edge (from RayHit.u)
//   hour_angle: Current hour hand angle (determines exit direction)
//   prism: The prism geometry (needed for bounce point coordinates)
//
// The bounce decision is based on comparing entry and exit faces:
//   - If entry and exit are on the same face, the ray would hug that edge → bounce needed
//   - If entry is at a vertex, bounce unless exit is on the "opposite" face (the one not
//     touching that vertex)
//
// IMPORTANT: We use find_prism_exit_from_center to determine the exit edge instead of
// angle-based determination. This ensures consistency with the actual rendered geometry,
// especially at vertex boundaries where angle-based methods can disagree with ray-casting.
static BounceInfo compute_bounce_info(
  int entry_edge,
  float entry_u,
  float hour_angle,
  const Prism* prism
) {
  BounceInfo info = {0, -1, 0.0f, 0.0f};

  // Validate entry_edge
  if (entry_edge < 0 || entry_edge > 2) return info;

  // Compute prism center from vertices
  float cx = (prism->vertices[0] + prism->vertices[2] + prism->vertices[4]) / 3.0f;
  float cy = (prism->vertices[1] + prism->vertices[3] + prism->vertices[5]) / 3.0f;

  // Get actual exit edge from geometry (not angle-based approximation).
  // This ensures the bounce decision matches the rendered exit point.
  RayHit exit_hit = find_prism_exit_from_center(cx, cy, hour_angle, prism);
  if (!exit_hit.hit) return info;  // No valid exit found, no bounce needed

  int entry_location = classify_edge_position(entry_edge, entry_u);
  int exit_location = classify_edge_position(exit_hit.edge_idx, exit_hit.u);

  int needs_bounce = 0;
  int bounce_idx = -1;

  if (entry_location >= 3) {
    // Entry at a vertex (3=v0, 4=v1, 5=v2)
    int vertex_idx = entry_location - 3;

    if (vertex_idx == 0) {
      // Entry at v0: bounce if exit is at/near v0 (on face 0, face 2, or vertex v0).
      // These paths would hug the edge. At other times (e.g., 04:00 with exit at v1),
      // the direct path through the interior is valid.
      int exit_touches_v0 = (exit_location == 0 || exit_location == 2 || exit_location == 3);
      if (exit_touches_v0) {
        // Use direction sign for robust tie-break (avoids angle wrap issues).
        // dx >= 0 means pointing right (face 0 side) → bounce through v2.
        // dx < 0 means pointing left (face 2 side) → bounce through v1.
        float dx = cosf_approx(hour_angle);
        bounce_idx = (dx >= 0.0f) ? 2 : 1;
        needs_bounce = 1;
      }
    } else {
      // Entry at v1 or v2 - bounce unless exit touches opposite face
      int opposite_face = (vertex_idx + 1) % 3;

      int exit_touches_opposite = 0;
      if (exit_location >= 3) {
        // Exit at vertex - vertex V touches face V and face (V+2)%3
        int exit_vertex = exit_location - 3;
        exit_touches_opposite = (exit_vertex == opposite_face) ||
                                ((exit_vertex + 2) % 3 == opposite_face);
      } else {
        // Exit on a face
        exit_touches_opposite = (exit_location == opposite_face);
      }

      if (!exit_touches_opposite) {
        needs_bounce = 1;
        bounce_idx = (exit_hit.edge_idx + 2) % 3;
      }
    }
  } else {
    // Entry on a face (0=right, 1=bottom, 2=left)
    int same_face_exit = (exit_location < 3) && (exit_location == entry_location);

    if (same_face_exit) {
      // Same face entry/exit: bounce through opposite vertex
      needs_bounce = 1;
      bounce_idx = (entry_location + 2) % 3;
    } else if (exit_location == 3) {
      // Exit at vertex v0: if entry is on a face touching v0 (face 0 or 2),
      // the direct path is too short - bounce through v1 or v2.
      int entry_touches_v0 = (entry_location == 0 || entry_location == 2);

      if (entry_touches_v0) {
        // Use direction sign for robust tie-break (avoids angle wrap issues).
        // dx >= 0 means pointing right (face 0 side) → bounce through v2.
        // dx < 0 means pointing left (face 2 side) → bounce through v1.
        float dx = cosf_approx(hour_angle);
        bounce_idx = (dx >= 0.0f) ? 2 : 1;
        needs_bounce = 1;
      }
    }
  }

  // Corner-hugging detection: entry near one vertex, exit on adjacent face but far from
  // that vertex. This creates a long flat internal path with minimal dispersion, followed
  // by sudden high dispersion outside - visually jarring.
  // Good paths (no bounce needed): entry and exit both near same vertex → short steep path.
  // Bad paths (bounce needed): entry near vertex V, exit far from V → long flat path.
  if (!needs_bounce && entry_location < 3 && exit_location < 3) {
    // Entry in last 20% of edge (u > 0.8) is considered "near the end vertex"
    const float CORNER_HUG_THRESHOLD = 0.8f;

    // Case 1: Entry near END of face. Example: 07:19 - entry near v1, exit far from v1.
    int next_face = (entry_edge + 1) % 3;
    if (entry_u > CORNER_HUG_THRESHOLD && exit_hit.edge_idx == next_face &&
        exit_hit.u > (1.0f - CORNER_HUG_THRESHOLD)) {
      needs_bounce = 1;
      bounce_idx = entry_edge;  // Start vertex of entry face (away from the hugged corner)
    }

    // Case 2: Entry near START of face. Example: 11:01 - entry near v0, exit far from v0.
    // Counter-example: 07:41 - entry near v2, exit also near v2 → no bounce needed.
    if (!needs_bounce) {
      int prev_face = (entry_edge + 2) % 3;
      if (entry_u < (1.0f - CORNER_HUG_THRESHOLD) && exit_hit.edge_idx == prev_face &&
          exit_hit.u < CORNER_HUG_THRESHOLD) {
        needs_bounce = 1;
        bounce_idx = (entry_edge + 1) % 3;  // End vertex of entry face
      }
    }
  }

  if (needs_bounce) {
    info.needs_bounce = 1;
    info.bounce_vertex_idx = bounce_idx;
    info.bounce_x = prism->vertices[bounce_idx * 2];
    info.bounce_y = prism->vertices[bounce_idx * 2 + 1];
  }

  return info;
}
