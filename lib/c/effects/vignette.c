#include "effects/vignette.h"
#include "config.h"
#include "effects/effect.h"
#include "fastmath.h"

// =================================================================================================
// Default Values
// =================================================================================================

// Default background grey level: 35/255 in sRGB space
#define VIGNETTE_DEFAULT_BACKGROUND 0.1372549f

// Default vignette strength: 40% max darkening at corners
#define VIGNETTE_DEFAULT_STRENGTH 0.4f

// =================================================================================================
// Effect Implementation
// =================================================================================================

void effect_vignette_apply(float *fb, int width, int height, const void *config,
                           const void *cache) {
  // If no config or geometry, nothing to do
  if (!config || !cache)
    return;

  const VignetteConfig *cfg = (const VignetteConfig *)config;

  // Skip if vignette disabled
  if (!cfg->enabled)
    return;

  const VignetteGeometry *geom = (const VignetteGeometry *)cache;

  // Get configuration values with defaults
  // strength: negative means use default, 0 means no darkening, positive means use that value
  // background: negative or zero means use default, positive means use that value
  float strength = cfg->strength >= 0.0f ? cfg->strength : VIGNETTE_DEFAULT_STRENGTH;
  float bg_base = cfg->background > 0.0f ? cfg->background : VIGNETTE_DEFAULT_BACKGROUND;

  // Circle bounds
  float cx = geom->cx;
  float cy = geom->cy;
  float radius = geom->radius;
  float r2 = radius * radius;

  // Maximum distance from center (diagonal to corner)
  float max_dist = sqrtf_impl((float)(width * width + height * height)) * 0.5f;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;

      // Only process pixels OUTSIDE the watch circle
      if (dist2 > r2) {
        int idx = row_offset + x * 4;

        // Calculate vignette factor based on distance from center
        float dist_from_center = sqrtf_impl(dist2);

        // Normalized distance: 0.0 at circle edge, 1.0 at max distance
        float vignette_t = clampf((dist_from_center - radius) / (max_dist - radius), 0.0f, 1.0f);

        // Smoothstep for perceptually smoother gradient
        // smoothstep(t) = t^2 * (3 - 2t)
        float smooth_t = vignette_t * vignette_t * (3.0f - 2.0f * vignette_t);

        // Vignette darkening factor: 1.0 at edge, (1.0 - strength) at max distance
        float vignette = 1.0f - smooth_t * strength;

        // Apply dithering noise to break up banding in dark gradients
        uint32_t hash = vignette_hash_pixel(x, y);
        // Noise in range [-1, +1], scaled to ~1 unit in 0-255 space (±0.5/255)
        float dither = ((float)(hash & 0xFF) / 255.0f - 0.5f) * (2.0f / 255.0f);

        // Final grey value with vignette and dither
        float grey = clampf(bg_base * vignette + dither, 0.0f, 1.0f);

        // Set pixel to grey background with full opacity
        fb[idx] = grey;
        fb[idx + 1] = grey;
        fb[idx + 2] = grey;
        fb[idx + 3] = 1.0f;
      }
    }
  }
}

// Effect descriptor
const Effect EFFECT_VIGNETTE = {.name = "vignette", .apply = effect_vignette_apply};
