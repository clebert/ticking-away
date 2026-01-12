#include "graphics.h"

#define WASM_EXPORT __attribute__((visibility("default")))

// =================================================================================================
// Application Constants
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)   // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f) // 30 degrees per hour

// =================================================================================================
// WASM Exports
// =================================================================================================

// Render the watchface.
// Parameters:
//   fb: framebuffer pointer (RGBA, width*height*4 bytes)
//   width, height: canvas dimensions
//   hour: 0-11
//   minute: 0-59.999... (fractional for smooth animation)
//   second: 0-59.999... (fractional for smooth sparkle animation on prism edge)
//   prism_size_percent: 10-90 (% of watch radius)
//   rainbow_spread: 0.0-1.0 (0 = no spread, 1 = 30 degrees)
//   minimal_mode: 0 or 1 (hide watch overlay when 1)
//   prism_r, prism_g, prism_b: 0-255 RGB values for prism stroke and internal rays
//   show_seconds: 0 or 1 (1 = show seconds sparkle on prism edge)
//   sparkle_size_percent: 1.0-10.0 (scale factor for sparkle size)
//   glow_width_percent: 0.05-0.50 (% of radius for glow width)
//   glow_intensity: 0.1-1.0 (intensity multiplier)
//   glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
//   ray_glow_width_percent: 0.0-0.10 (% of radius for ray glow width)
//   ray_glow_intensity: 0.0-1.0 (ray glow intensity multiplier)
//   ray_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
//   internal_ray_real_colors: 0 or 1 (1 = use wavelength-based colors for internal rays)
//   artistic_dispersion: 0 or 1 (1 = artistic dispersion with red first, 0 = physical where violet bends most)
WASM_EXPORT void render_watchface(uint8_t *fb, int width, int height, int hour, float minute,
                                  float second, float prism_size_percent, float rainbow_spread,
                                  int minimal_mode, int prism_r, int prism_g, int prism_b,
                                  int show_seconds, float sparkle_size_percent,
                                  float glow_width_percent, float glow_intensity, int glow_falloff,
                                  float ray_glow_width_percent, float ray_glow_intensity,
                                  int ray_glow_falloff, int internal_ray_real_colors,
                                  int artistic_dispersion) {
  // Calculate watch geometry
  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (width < height ? (float)width : (float)height) / 2.0f - 1.0f;

  // Create prism (apex up, 60 degrees, no rotation)
  float prism_size = (prism_size_percent / 100.0f) * radius;
  Prism prism;
  create_prism(cx, cy, prism_size, 60.0f, &prism);

  // Calculate minute position (light source on circle edge)
  float minute_angle = ANGLE_0 + (minute / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  // Calculate hour angle (target) with minute interpolation
  // Hour position advances smoothly as minutes progress
  float hour12 = (float)hour; // 0-11 for angles
  float hour_angle = ANGLE_0 + (hour12 / 12.0f) * TAU + (minute / 60.0f) * HOUR_ARC;

  // Render the watchface scene
  float ray_glow_width = ray_glow_width_percent * radius;
  render_watchface_scene(fb, width, height, cx, cy, radius, entry_x, entry_y, hour_angle,
                         rainbow_spread, second, &prism, minimal_mode, (uint8_t)prism_r,
                         (uint8_t)prism_g, (uint8_t)prism_b, show_seconds, sparkle_size_percent,
                         glow_width_percent, glow_intensity, glow_falloff, ray_glow_width,
                         ray_glow_intensity, ray_glow_falloff, internal_ray_real_colors,
                         artistic_dispersion);
}
