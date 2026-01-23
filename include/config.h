#pragma once

#include <stdint.h>

// =================================================================================================
// Watchface Configuration Struct
// =================================================================================================
// All fields are int32 or float32 (4 bytes each) to avoid padding issues when
// accessing from JavaScript via typed arrays.

typedef struct {
  // Time
  int32_t hour;                      // 0-11
  float minute;                      // 0-59.999 (fractional for smooth animation)

  // Prism geometry and glow
  float prism_size_percent;          // 10-90 (% of watch radius)
  float rainbow_spread;              // 0.0-1.0 (0 = no spread, 1 = 30 degrees)
  int32_t prism_r;                   // 0-255 RGB for prism stroke
  int32_t prism_g;
  int32_t prism_b;
  float glow_width_percent;          // 0.05-0.50 (% of radius)
  float glow_intensity;              // 0.1-1.0
  int32_t glow_falloff;              // 0=linear, 1=quadratic, 2=cubic, 3=exponential

  // Ray settings
  float ray_glow_width_percent;      // 0.0-0.10 (% of radius)
  float ray_glow_intensity;          // 0.0-1.0
  int32_t ray_glow_falloff;          // 0=linear, 1=quadratic, 2=cubic, 3=exponential
  int32_t gradient_fill;             // 0 or 1
  int32_t palette;                   // 0-4 (color palette)
  int32_t reverse_spectrum;          // 0 or 1 (album art style)

  // Marker settings
  int32_t show_markers;              // 0 or 1
  float marker_length_percent;       // 0.0-0.20
  float marker_glow_width_percent;   // 0.0-0.05 (% of radius)
  float marker_glow_intensity;       // 0.0-1.0
  int32_t marker_glow_falloff;       // 0=linear, 1=quadratic, 2=cubic, 3=exponential

  // Background settings
  float grain_intensity;             // 0.0-1.0
  float grain_scale;                 // DPR to scale grain size
  int32_t grain_prism_only;          // 0 or 1
  float grain_brightness_threshold;  // 0.01-1.0
  int32_t vignette;                  // 0 or 1

  // Dithering settings (for e-ink display output)
  int32_t dither_enabled;            // 0 or 1
  int32_t dither_palette_mode;       // 0 = IDEAL, 1 = DEVICE, 2 = BLEND
  float dither_palette_saturation;   // 0.0-1.0: blend factor (only used when mode=BLEND)
  float dither_strength;             // 0.0-1.0: intensity of dither pattern (default 0.2)
  int32_t dither_kernel;             // 0 = ATKINSON, 1 = FLOYD_STEINBERG
  int32_t dither_oklab_error;        // 0 = linear RGB error diffusion, 1 = OkLab error diffusion
  int32_t dither_clean_background;   // 0 or 1: force background pixels to palette black (no dither noise)

  // Debug output (written by render, read by JS)
  float entry_u;                     // Parametric position of entry point on prism edge (0-1)
  float exit_u;                      // Parametric position of exit point on prism edge (0-1)

} WatchfaceConfig;
