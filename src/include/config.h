#pragma once

#include <stdint.h>

// =================================================================================================
// Watchface Configuration Struct
// =================================================================================================
// All fields are int32 or float32 (4 bytes each) to avoid padding issues when
// accessing from JavaScript via typed arrays.

typedef struct {
  // Time
  int hour;      // 0-11
  float minute;  // 0-59.999 (fractional for smooth animation)

  // Prism geometry and glow
  float prism_size_percent;   // 10-90 (% of watch radius)
  float rainbow_spread;       // 0.0-1.0 (0 = no spread, 1 = 30 degrees)
  int prism_r;                // 0-255 RGB for prism stroke
  int prism_g;
  int prism_b;
  float glow_width_percent;   // 0.05-0.50 (% of radius)
  float glow_intensity;       // 0.1-1.0
  int glow_falloff;           // 0=linear, 1=quadratic, 2=cubic, 3=exponential

  // Ray settings
  float ray_glow_width_percent;  // 0.0-0.10 (% of radius)
  float ray_glow_intensity;      // 0.0-1.0
  int ray_glow_falloff;          // 0=linear, 1=quadratic, 2=cubic, 3=exponential
  int gradient_fill;             // 0 or 1
  int palette;                   // 0-4 (color palette)
  int reverse_spectrum;          // 0 or 1 (album art style)

  // Marker settings
  int show_markers;                 // 0 or 1
  float marker_length_percent;      // 0.0-0.20
  float marker_glow_width_percent;  // 0.0-0.05 (% of radius)
  float marker_glow_intensity;      // 0.0-1.0
  int marker_glow_falloff;          // 0=linear, 1=quadratic, 2=cubic, 3=exponential

  // Background settings
  float grain_intensity;             // 0.0-1.0
  float grain_scale;                 // DPR to scale grain size
  int grain_prism_only;              // 0 or 1
  float grain_brightness_threshold;  // 0.01-1.0
  int vignette;                      // 0 or 1
} WatchfaceConfig;
