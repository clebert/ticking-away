// =================================================================================================
// Prism Glow Layer Implementation
// =================================================================================================
// Renders the inner glow effect on prism edges. The glow extends inward from each edge,
// creating a soft highlight that emphasizes the triangular prism shape.

#include "layers/prism_glow.h"
#include "config.h"
#include "draw/pixel.h"
#include "fastmath.h"
#include "geometry/prism.h"
#include "geometry/segment.h"

// =================================================================================================
// Smooth Minimum
// =================================================================================================

float smooth_min(float a, float b, float k) {
  // Polynomial smooth minimum - blends smoothly between a and b
  // when they are within 'k' of each other. This eliminates the gradient
  // discontinuity (visible crease) that occurs with hard min at corners.
  float h = maxf_impl(k - fabsf_impl(a - b), 0.0f) / k;
  return minf_impl(a, b) - h * h * k * 0.25f;
}

// =================================================================================================
// Distance Functions
// =================================================================================================

float prism_min_edge_distance(float px, float py, const Prism *prism, float smooth_k) {
  // Get prism vertices
  float v0x, v0y, v1x, v1y, v2x, v2y;
  prism_get_vertex(prism, 0, &v0x, &v0y);
  prism_get_vertex(prism, 1, &v1x, &v1y);
  prism_get_vertex(prism, 2, &v2x, &v2y);

  // Compute distance to each edge
  float d0 = point_to_segment_distance(px, py, v0x, v0y, v1x, v1y);
  float d1 = point_to_segment_distance(px, py, v1x, v1y, v2x, v2y);
  float d2 = point_to_segment_distance(px, py, v2x, v2y, v0x, v0y);

  // Chain smooth_min for all three edges
  return smooth_min(smooth_min(d0, d1, smooth_k), d2, smooth_k);
}

// =================================================================================================
// Glow Drawing
// =================================================================================================

void prism_glow_draw(float *fb, int width, int height, const Prism *prism, float r, float g,
                     float b, float glow_width, float intensity, FalloffType falloff) {
  // Get prism vertices for bounding box and containment test
  float v0x, v0y, v1x, v1y, v2x, v2y;
  prism_get_vertex(prism, 0, &v0x, &v0y);
  prism_get_vertex(prism, 1, &v1x, &v1y);
  prism_get_vertex(prism, 2, &v2x, &v2y);

  // Compute bounding box
  float min_x = v0x < v1x ? (v0x < v2x ? v0x : v2x) : (v1x < v2x ? v1x : v2x);
  float max_x = v0x > v1x ? (v0x > v2x ? v0x : v2x) : (v1x > v2x ? v1x : v2x);
  float min_y = v0y < v1y ? (v0y < v2y ? v0y : v2y) : (v1y < v2y ? v1y : v2y);
  float max_y = v0y > v1y ? (v0y > v2y ? v0y : v2y) : (v1y > v2y ? v1y : v2y);

  // Clamp to framebuffer bounds with small margin
  int x_start = (int)min_x - 1;
  int x_end = (int)max_x + 2;
  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (x_start < 0)
    x_start = 0;
  if (y_start < 0)
    y_start = 0;
  if (x_end > width)
    x_end = width;
  if (y_end > height)
    y_end = height;

  // Smoothing factor for corner blending
  float smooth_k = glow_width * 0.5f;

  for (int y = y_start; y < y_end; y++) {
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;

      // Only draw inside the prism
      if (!point_in_triangle(px, py, v0x, v0y, v1x, v1y, v2x, v2y)) {
        continue;
      }

      // Compute smooth minimum distance to edges
      float dist = prism_min_edge_distance(px, py, prism, smooth_k);

      // Apply glow within the glow width
      if (dist < glow_width) {
        float t = dist / glow_width;
        float falloff_value = compute_falloff(falloff, t);

        float alpha = falloff_value * intensity;
        pixel_add(fb, width, height, x, y, r, g, b, alpha);
      }
    }
  }
}

// =================================================================================================
// Layer Interface
// =================================================================================================

void layer_prism_glow_render(const RenderContext *ctx) {
  if (!ctx->glow_config || !ctx->prism) {
    return;
  }

  const GlowConfig *cfg = ctx->glow_config;

  // Convert RGB from 0-255 to 0.0-1.0 linear space
  // Note: The config stores sRGB values, so we should convert to linear.
  // For now, use simple /255 conversion (close enough for glow colors)
  float r = (float)cfg->r / 255.0f;
  float g = (float)cfg->g / 255.0f;
  float b = (float)cfg->b / 255.0f;

  // Glow width is specified as fraction of radius
  float glow_width = ctx->radius * cfg->width;

  prism_glow_draw(ctx->fb, ctx->width, ctx->height, ctx->prism, r, g, b, glow_width, cfg->intensity,
                  cfg->falloff);
}

// Layer descriptor
const Layer LAYER_PRISM_GLOW = {.name = "prism_glow", .render = layer_prism_glow_render};
