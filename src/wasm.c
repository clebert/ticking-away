#include "config.h"
#include "prism.h"
#include "watchface.h"

#define WASM_EXPORT __attribute__((visibility("default")))

// =================================================================================================
// Application Constants
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)   // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f) // 30 degrees per hour

// =================================================================================================
// Static Configuration
// =================================================================================================

static WatchfaceConfig config;

// =================================================================================================
// WASM Exports
// =================================================================================================

extern unsigned char __heap_base; // First byte after static data (provided by the linker)

// Get the address where it's safe to allocate
WASM_EXPORT void *get_heap_base(void) { return &__heap_base; }

// Get pointer to the config struct (returns byte offset into memory.buffer)
WASM_EXPORT WatchfaceConfig *get_config(void) { return &config; }

// Render the watchface using the static config.
// Only framebuffer pointers and dimensions are passed as parameters since
// they depend on canvas size which may change.
WASM_EXPORT void render_watchface(float *float_fb, uint8_t *fb, int width, int height) {
  // Calculate watch geometry
  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (width < height ? (float)width : (float)height) / 2.0f - 1.0f;

  // Create prism (apex up, 60 degrees, no rotation)
  float prism_size = (config.prism_size_percent / 100.0f) * radius;
  Prism prism;
  create_prism(cx, cy, prism_size, 60.0f, &prism);

  // Calculate minute position (light source on circle edge)
  float minute_angle = ANGLE_0 + (config.minute / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  // Calculate hour angle (target) with minute interpolation
  // Hour position advances smoothly as minutes progress
  float hour12 = (float)config.hour; // 0-11 for angles
  float hour_angle = ANGLE_0 + (hour12 / 12.0f) * TAU + (config.minute / 60.0f) * HOUR_ARC;

  // Compute entry_u (where minute ray enters prism)
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);
  RayHit prism_entry = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, &prism);
  config.entry_u = prism_entry.hit ? prism_entry.u : -1.0f;

  // Compute exit_u (where hour ray exits prism)
  RayHit prism_exit = find_prism_exit_from_center(cx, cy, hour_angle, &prism);
  config.exit_u = prism_exit.hit ? prism_exit.u : -1.0f;

  // Render the watchface scene
  float ray_glow_width = config.ray_glow_width_percent * radius;
  render_watchface_scene(
      float_fb, fb, width, height, cx, cy, radius, entry_x, entry_y, hour_angle,
      config.rainbow_spread, &prism, config.show_markers, (uint8_t)config.prism_r,
      (uint8_t)config.prism_g, (uint8_t)config.prism_b, config.glow_width_percent,
      config.glow_intensity, config.glow_falloff, ray_glow_width, config.ray_glow_intensity,
      config.ray_glow_falloff, config.marker_length_percent, config.marker_glow_width_percent,
      config.marker_glow_intensity, config.marker_glow_falloff, config.grain_intensity,
      config.grain_scale, config.grain_prism_only, config.gradient_fill, config.vignette,
      config.palette, config.reverse_spectrum, config.grain_brightness_threshold);
}
