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

// Determine which vertex a point on a face is near, based on its parametric position.
// face: The face index (0, 1, or 2)
// u: Parametric position along face (0.0=start vertex, 1.0=end vertex)
// threshold: Distance threshold for "near" (as fraction of edge length)
// Returns: Vertex index (0=v0, 1=v1, 2=v2) if near a vertex, -1 if not near any.
static int get_nearby_vertex(int face, float u, float threshold) {
  if (threshold <= 0.0f) return -1;  // Disabled when threshold is zero
  if (u < threshold) {
    // Near start vertex: face 0→v0, face 1→v1, face 2→v2
    return face;
  } else if (u >= 1.0f - threshold) {
    // Near end vertex: face 0→v1, face 1→v2, face 2→v0
    return (face + 1) % 3;
  }
  return -1;
}

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

// Edge path from entry point to bounce vertex (travels along prism edges outside)
// The path consists of up to 3 points: entry → [optional intermediate vertex] → bounce vertex
typedef struct {
  int num_points;          // 2 or 3 points in the path
  float points[6];         // Up to 3 points: (x0,y0), (x1,y1), (x2,y2)
} EdgePath;

// Compute the path along prism edges from entry point to target vertex.
// The entry point is on edge entry_edge at position (entry_x, entry_y).
// Returns an EdgePath with 2 points (direct to adjacent vertex) or 3 points (via intermediate vertex).
// Always chooses the shortest path.
static EdgePath compute_shortest_edge_path(
  int entry_edge,
  float entry_x, float entry_y,
  int target_vertex,
  const Prism* prism
) {
  EdgePath path = {0, {0}};

  // Start point is always the entry point
  path.points[0] = entry_x;
  path.points[1] = entry_y;

  // Edge E connects vertex E to vertex (E+1)%3
  // So edge 0: v0→v1, edge 1: v1→v2, edge 2: v2→v0
  int start_vertex = entry_edge;           // Vertex at start of entry edge
  int end_vertex = (entry_edge + 1) % 3;   // Vertex at end of entry edge

  // Get vertex coordinates
  float vx[3] = {prism->vertices[0], prism->vertices[2], prism->vertices[4]};
  float vy[3] = {prism->vertices[1], prism->vertices[3], prism->vertices[5]};

  // Compute distance from entry point to each end of the entry edge
  float dx_start = vx[start_vertex] - entry_x;
  float dy_start = vy[start_vertex] - entry_y;
  float dist_to_start = sqrtf_impl(dx_start * dx_start + dy_start * dy_start);

  float dx_end = vx[end_vertex] - entry_x;
  float dy_end = vy[end_vertex] - entry_y;
  float dist_to_end = sqrtf_impl(dx_end * dx_end + dy_end * dy_end);

  // If target is one of the adjacent vertices, go directly
  if (target_vertex == start_vertex) {
    path.num_points = 2;
    path.points[2] = vx[target_vertex];
    path.points[3] = vy[target_vertex];
    return path;
  }
  if (target_vertex == end_vertex) {
    path.num_points = 2;
    path.points[2] = vx[target_vertex];
    path.points[3] = vy[target_vertex];
    return path;
  }

  // Target is the opposite vertex (not adjacent to entry edge)
  // Two paths: via start_vertex or via end_vertex
  // Compute edge lengths for each path

  // Path via start_vertex: entry → start_vertex → target_vertex
  // Distance = dist_to_start + edge_length(start_vertex to target_vertex)
  float edge_start_dx = vx[target_vertex] - vx[start_vertex];
  float edge_start_dy = vy[target_vertex] - vy[start_vertex];
  float edge_start_len = sqrtf_impl(edge_start_dx * edge_start_dx + edge_start_dy * edge_start_dy);
  float path_via_start = dist_to_start + edge_start_len;

  // Path via end_vertex: entry → end_vertex → target_vertex
  float edge_end_dx = vx[target_vertex] - vx[end_vertex];
  float edge_end_dy = vy[target_vertex] - vy[end_vertex];
  float edge_end_len = sqrtf_impl(edge_end_dx * edge_end_dx + edge_end_dy * edge_end_dy);
  float path_via_end = dist_to_end + edge_end_len;

  // Choose the shortest path
  int use_start_path = (path_via_start <= path_via_end);

  // Build the chosen path
  path.num_points = 3;
  if (use_start_path) {
    path.points[2] = vx[start_vertex];
    path.points[3] = vy[start_vertex];
    path.points[4] = vx[target_vertex];
    path.points[5] = vy[target_vertex];
  } else {
    path.points[2] = vx[end_vertex];
    path.points[3] = vy[end_vertex];
    path.points[4] = vx[target_vertex];
    path.points[5] = vy[target_vertex];
  }

  return path;
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
  const Prism* prism,
  float entry_vertex_proximity,
  float exit_vertex_proximity,
  int simple_bounce
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

  // Simple bounce mode: always bounce through the opposite vertex of the exit face.
  // The exit face is determined by the hour angle, so this bounces through
  // the vertex opposite to where the hour hand is pointing.
  if (simple_bounce) {
    int bounce_idx = (exit_hit.edge_idx + 2) % 3;

    info.needs_bounce = 1;
    info.bounce_vertex_idx = bounce_idx;
    info.bounce_x = prism->vertices[bounce_idx * 2];
    info.bounce_y = prism->vertices[bounce_idx * 2 + 1];

    return info;
  }

  // Complex bounce mode: conditionally bounce based on entry/exit face relationships
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
    } else if (exit_location < 3 && exit_location != entry_location) {
      // Exit on a different face - check if entry is near a shared vertex.
      // When entry is near a vertex and exit is on the adjacent face, the direct
      // path is cramped regardless of where on the adjacent face the exit is.
      // Bounce through the opposite vertex for better dispersion.
      int entry_near = get_nearby_vertex(entry_location, entry_u, entry_vertex_proximity);

      if (entry_near >= 0) {
        // Entry is near vertex entry_near. Check if exit is on the other adjacent face.
        // Vertex V is shared by faces V and (V+2)%3.
        int face_a = entry_near;
        int face_b = (entry_near + 2) % 3;
        int other_adjacent_face = (entry_location == face_a) ? face_b : face_a;

        if (exit_location == other_adjacent_face) {
          // Exit is on the adjacent face to the shared vertex.
          // Check if exit is near the OTHER vertex on that face (not entry_near).
          // If exit is near that other vertex, the path crosses the interior well - no bounce needed.
          int exit_near = get_nearby_vertex(other_adjacent_face, exit_hit.u, exit_vertex_proximity);

          // Only bounce if exit is NOT near the non-shared vertex:
          // - exit_near < 0: not near any vertex, path is cramped, bounce needed
          // - exit_near == entry_near: near the shared vertex, still cramped, bounce needed
          // - exit_near != entry_near: near the other vertex, path is fine, no bounce
          if (exit_near < 0 || exit_near == entry_near) {
            needs_bounce = 1;
            bounce_idx = (exit_location + 2) % 3;
          }
        }
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
