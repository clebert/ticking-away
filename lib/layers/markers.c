// =================================================================================================
// Markers Layer Implementation
// =================================================================================================
// Renders the 12 hour markers around the watch face. Each marker is a glowing line extending
// inward from near the watch edge, positioned at clock positions (12, 1, 2, ..., 11).

#include "layers/markers.h"
#include "draw/line.h"
#include "fastmath.h"

#include <stddef.h>

// =================================================================================================
// Constants
// =================================================================================================

#define NUM_MARKERS 12
#define MARKER_OUTER_PERCENT 0.98f // Markers end at 98% of radius

// =================================================================================================
// Marker Drawing
// =================================================================================================

void markers_draw(float *fb, int width, int height, float cx, float cy, float radius,
                  const MarkerConfig *config) {
  // Glow width is specified as fraction of radius
  float glow_width = radius * config->glow_width;

  // Circle clipping region
  float circle_clip[3] = {cx, cy, radius};

  for (int h = 0; h < NUM_MARKERS; h++) {
    // Calculate angle: h=0 is 12 o'clock, h=3 is 3 o'clock, etc.
    // Standard clock: 0 degrees is 3 o'clock, so we offset by -3 hours
    // and each hour is 30 degrees (360/12)
    float angle = ((float)h - 3.0f) * 30.0f * PI / 180.0f;

    // Inner and outer radii for the marker line
    float inner_r = radius * (1.0f - config->length);
    float outer_r = radius * MARKER_OUTER_PERCENT;

    // Calculate endpoints
    float cos_a = cosf_approx(angle);
    float sin_a = sinf_approx(angle);
    float x0 = cx + cos_a * inner_r;
    float y0 = cy + sin_a * inner_r;
    float x1 = cx + cos_a * outer_r;
    float y1 = cy + sin_a * outer_r;

    // Draw marker with pure white color
    line_draw_glow(fb, width, height, x0, y0, x1, y1, 1.0f, 1.0f, 1.0f, // Pure white
                   glow_width, config->glow_intensity, config->falloff,
                   NULL,        // No triangle clip
                   circle_clip, // Clip to watch circle
                   NULL         // No exclude region
    );
  }
}

// =================================================================================================
// Layer Interface
// =================================================================================================

void layer_markers_render(const RenderContext *ctx) {
  // Skip if no config or markers not visible
  if (!ctx->marker_config || !ctx->marker_config->visible) {
    return;
  }

  markers_draw(ctx->fb, ctx->width, ctx->height, ctx->cx, ctx->cy, ctx->radius, ctx->marker_config);
}

// Layer descriptor
const Layer LAYER_MARKERS = {.name = "markers", .render = layer_markers_render};
