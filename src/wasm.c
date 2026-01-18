#include "include/watchface.h"

#define WASM_EXPORT __attribute__((visibility("default")))

// =================================================================================================
// Application Constants
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)   // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f) // 30 degrees per hour

// =================================================================================================
// WASM Exports
// =================================================================================================

extern unsigned char __heap_base; // First byte after static data (provided by the linker)

// Get the address where it's safe to allocate
WASM_EXPORT void *get_heap_base(void) { return &__heap_base; }

// Render the watchface.
// Parameters:
//   float_fb: float framebuffer for linear rendering (RGBA, width*height*16 bytes)
//   fb: output framebuffer pointer (RGBA, width*height*4 bytes)
//   width, height: canvas dimensions
//   hour: 0-11
//   minute: 0-59.999... (fractional for smooth animation)
//   prism_size_percent: 10-90 (% of watch radius)
//   rainbow_spread: 0.0-1.0 (0 = no spread, 1 = 30 degrees)
//   show_markers: 0 or 1 (show watch overlay when 1)
//   prism_r, prism_g, prism_b: 0-255 RGB values for prism stroke
//   glow_width_percent: 0.05-0.50 (% of radius for glow width)
//   glow_intensity: 0.1-1.0 (intensity multiplier)
//   glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
//   ray_glow_width_percent: 0.0-0.10 (% of radius for ray glow width)
//   ray_glow_intensity: 0.0-1.0 (ray glow intensity multiplier)
//   ray_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
//   marker_length_percent: 0.0-0.20 (how far markers extend towards center)
//   marker_glow_width_percent: 0.0-0.05 (% of radius for marker glow width)
//   marker_glow_intensity: 0.0-1.0 (marker glow intensity multiplier)
//   marker_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
//   grain_intensity: 0.0-1.0 (intensity of film grain effect)
//   grain_scale: device pixel ratio to scale grain size (1.0 = no scaling)
//   grain_prism_only: 0 or 1 (1 = only apply grain inside prism)
//   grain_brightness_threshold: 0.01-1.0 (brightness at which grain reaches full intensity)
//   gradient_fill: 0 or 1 (1 = fill gradient between rainbow rays)
//   vignette: 0 or 1 (1 = apply vignette to background)
//   palette: 0-4 (color palette: 0=OkLCH Balanced, 1=Saturated, 2=Spectral, 3=Neon, 4=Muted)
//   reverse_spectrum: 0 or 1 (1 = reverse spectral order, album art style)
WASM_EXPORT void
render_watchface(float *float_fb, uint8_t *fb, int width, int height, int hour, float minute,
                 float prism_size_percent, float rainbow_spread, int show_markers, int prism_r,
                 int prism_g, int prism_b, float glow_width_percent, float glow_intensity,
                 int glow_falloff, float ray_glow_width_percent, float ray_glow_intensity,
                 int ray_glow_falloff, float marker_length_percent, float marker_glow_width_percent,
                 float marker_glow_intensity, int marker_glow_falloff, float grain_intensity,
                 float grain_scale, int grain_prism_only, float grain_brightness_threshold,
                 int gradient_fill, int vignette, int palette, int reverse_spectrum) {
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
  render_watchface_scene(
      float_fb, fb, width, height, cx, cy, radius, entry_x, entry_y, hour_angle, rainbow_spread,
      &prism, show_markers, (uint8_t)prism_r, (uint8_t)prism_g, (uint8_t)prism_b,
      glow_width_percent, glow_intensity, glow_falloff, ray_glow_width, ray_glow_intensity,
      ray_glow_falloff, marker_length_percent, marker_glow_width_percent, marker_glow_intensity,
      marker_glow_falloff, grain_intensity, grain_scale, grain_prism_only, gradient_fill, vignette,
      palette, reverse_spectrum, grain_brightness_threshold);
}
