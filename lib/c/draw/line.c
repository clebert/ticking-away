#include "draw/line.h"
#include "draw/pixel.h"
#include "fastmath.h"
#include "geometry/prism.h"
#include "geometry/segment.h"
#include "geometry/types.h"

// =================================================================================================
// Line Drawing with Glow (Gradient Intensity)
// =================================================================================================

void line_draw_glow_gradient(float *fb, int width, int height, float x0, float y0, float x1,
                             float y1, float r, float g, float b, float glow_width,
                             float intensity_start, float intensity_end, FalloffType falloff,
                             ClipTriangle clip_triangle, ClipCircle clip_circle,
                             ExcludeTriangle exclude_triangle) {
  Segment seg;
  segment_init(&seg, x0, y0, x1, y1);
  float glow_width_sq = glow_width * glow_width;

  // Compute y-range for iteration
  float min_y = (y0 < y1 ? y0 : y1) - glow_width;
  float max_y = (y0 > y1 ? y0 : y1) + glow_width;

  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (y_start < 0)
    y_start = 0;
  if (y_end > height)
    y_end = height;

  // Iterate over scanlines
  for (int y = y_start; y < y_end; y++) {
    float py = (float)y + 0.5f;

    // Find x-interval where capsule intersects this scanline
    int x_lo, x_hi;
    if (!capsule_scanline_intersect(py, &seg, glow_width, &x_lo, &x_hi)) {
      continue;
    }

    if (x_lo < 0)
      x_lo = 0;
    if (x_hi > width)
      x_hi = width;

    // Iterate over pixels in the x-interval
    for (int x = x_lo; x < x_hi; x++) {
      float px = (float)x + 0.5f;

      // Triangle clipping
      if (clip_triangle &&
          !point_in_triangle(px, py, clip_triangle[0], clip_triangle[1], clip_triangle[2],
                             clip_triangle[3], clip_triangle[4], clip_triangle[5])) {
        continue;
      }

      // Circle clipping
      if (clip_circle) {
        float dx = px - clip_circle[0];
        float dy = py - clip_circle[1];
        if (dx * dx + dy * dy > clip_circle[2] * clip_circle[2]) {
          continue;
        }
      }

      // Triangle exclusion
      if (exclude_triangle &&
          point_in_triangle(px, py, exclude_triangle[0], exclude_triangle[1], exclude_triangle[2],
                            exclude_triangle[3], exclude_triangle[4], exclude_triangle[5])) {
        continue;
      }

      // Get distance and position along line
      float line_t;
      float dist_sq = segment_point_distance_sq_with_t(&seg, px, py, &line_t);
      if (dist_sq >= glow_width_sq)
        continue;

      float dist = sqrtf_impl(dist_sq);
      float t = dist / glow_width;
      float falloff_value = compute_falloff(falloff, t);

      // Interpolate intensity based on position along line
      float intensity = intensity_start + (intensity_end - intensity_start) * line_t;

      float alpha = falloff_value * intensity;
      pixel_add(fb, width, height, x, y, r, g, b, alpha);
    }
  }
}

// =================================================================================================
// Line Drawing with Glow (Uniform Intensity)
// =================================================================================================

void line_draw_glow(float *fb, int width, int height, float x0, float y0, float x1, float y1,
                    float r, float g, float b, float glow_width, float intensity,
                    FalloffType falloff, ClipTriangle clip_triangle, ClipCircle clip_circle,
                    ExcludeTriangle exclude_triangle) {
  line_draw_glow_gradient(fb, width, height, x0, y0, x1, y1, r, g, b, glow_width, intensity,
                          intensity, falloff, clip_triangle, clip_circle, exclude_triangle);
}
