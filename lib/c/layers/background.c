// =================================================================================================
// Background Layer Implementation
// =================================================================================================
// Initializes the framebuffer with pure black inside the watch circle and transparent black
// outside. This provides a clean canvas for subsequent layers.

#include "layers/background.h"

// -------------------------------------------------------------------------------------------------
// Implementation
// -------------------------------------------------------------------------------------------------

void layer_background_render(const RenderContext *ctx) {
  float *fb = ctx->fb;
  int width = ctx->width;
  int height = ctx->height;
  float cx = ctx->cx;
  float cy = ctx->cy;
  float radius = ctx->radius;

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;
      int idx = row_offset + x * 4;

      if (dist2 <= r2) {
        // Inside watchface - pure black with full alpha
        fb[idx] = 0.0f;
        fb[idx + 1] = 0.0f;
        fb[idx + 2] = 0.0f;
        fb[idx + 3] = 1.0f;
      } else {
        // Outside watchface - white with full alpha (for e-ink displays)
        fb[idx] = 1.0f;
        fb[idx + 1] = 1.0f;
        fb[idx + 2] = 1.0f;
        fb[idx + 3] = 1.0f;
      }
    }
  }
}

// Layer descriptor
const Layer LAYER_BACKGROUND = {.name = "background", .render = layer_background_render};
