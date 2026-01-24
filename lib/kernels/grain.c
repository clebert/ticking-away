#include "kernels/grain.h"
#include "config.h"
#include "fastmath.h"
#include "kernels/kernel.h"

#ifndef NULL
#define NULL ((void *)0)
#endif

// =================================================================================================
// Helper Functions
// =================================================================================================

// Point-in-triangle test using barycentric coordinates
// Returns 1 if point (px, py) is inside triangle, 0 otherwise
static int grain_point_in_triangle(float px, float py, float x0, float y0, float x1, float y1,
                                   float x2, float y2) {
  float denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
  // Check for degenerate triangle
  if (denom > -0.0001f && denom < 0.0001f)
    return 0;

  float a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denom;
  float b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denom;
  float c = 1.0f - a - b;

  return (a >= 0.0f && b >= 0.0f && c >= 0.0f);
}

// =================================================================================================
// Kernel Implementation
// =================================================================================================

void kernel_grain_apply(float *fb, int width, int height, const void *config, const void *cache) {
  // If no config, no grain to apply
  if (!config)
    return;

  const GrainConfig *cfg = (const GrainConfig *)config;

  // Skip if grain disabled
  if (cfg->intensity <= 0.0f)
    return;

  // Get geometry context (optional)
  const GrainGeometry *geom = (const GrainGeometry *)cache;

  // Grain strength in sRGB space: ±6% at full intensity (≈ ±15/255, classic film grain)
  // Applied in perceptual space for uniform noise across all brightness levels.
  float grain_strength = cfg->intensity * 0.06f;

  // Brightness threshold (0-1) at which grain reaches full intensity.
  // Below this, grain fades linearly to zero (avoids noise on black areas).
  float threshold = cfg->threshold > 0.0f ? cfg->threshold : 0.1f;
  float brightness_scale = 1.0f / threshold;

  // Circle bounds (if geometry provided)
  float cx = 0.0f, cy = 0.0f, r2 = 0.0f;
  int use_circle_mask = 0;
  if (geom) {
    cx = geom->cx;
    cy = geom->cy;
    r2 = geom->radius * geom->radius;
    use_circle_mask = 1;
  }

  // Prism vertices (if prism_only mode)
  const float *prism = nullptr;
  if (cfg->prism_only && geom && geom->prism_vertices) {
    prism = geom->prism_vertices;
  }

  // Grain scale (for DPR scaling)
  float scale = cfg->scale > 0.0f ? cfg->scale : 1.0f;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int idx = (y * width + x) * 4;

      // Circle mask check
      if (use_circle_mask) {
        float px = (float)x + 0.5f;
        float py = (float)y + 0.5f;
        float dx = px - cx;
        float dy = py - cy;
        float dist_sq = dx * dx + dy * dy;

        if (dist_sq > r2) {
          continue; // Skip pixels outside circle
        }

        // Prism-only check
        if (prism) {
          int in_prism = grain_point_in_triangle(px, py, prism[0], prism[1], prism[2], prism[3],
                                                 prism[4], prism[5]);
          if (!in_prism) {
            continue; // Skip pixels outside prism
          }
        }
      }

      // Get current sRGB values
      float r = fb[idx];
      float g = fb[idx + 1];
      float b = fb[idx + 2];

      // Calculate brightness (simple average in sRGB space)
      float brightness = (r + g + b) / 3.0f;

      // Scale grain intensity by brightness (fades to zero in dark areas)
      float brightness_factor = clampf(brightness * brightness_scale, 0.0f, 1.0f);

      // Generate deterministic noise using scaled coordinates
      int gx = (int)((float)x / scale);
      int gy = (int)((float)y / scale);
      uint32_t hash = grain_hash_pixel(gx, gy);

      // Convert hash to noise value: [-grain_strength, +grain_strength]
      float noise = ((float)(hash & 0xFF) / 255.0f - 0.5f) * grain_strength * 2.0f;

      // Apply brightness-scaled noise
      float grain = noise * brightness_factor;

      // Add grain to all channels (monochromatic grain)
      fb[idx] = clampf(r + grain, 0.0f, 1.0f);
      fb[idx + 1] = clampf(g + grain, 0.0f, 1.0f);
      fb[idx + 2] = clampf(b + grain, 0.0f, 1.0f);
      // Alpha unchanged
    }
  }
}

// Kernel descriptor
const Kernel KERNEL_GRAIN = {.name = "grain", .apply = kernel_grain_apply};
