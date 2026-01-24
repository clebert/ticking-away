// =================================================================================================
// WASM Module
// =================================================================================================
// Uses the modular Scene + Pipeline APIs instead of the monolithic render_watchface_scene().

#include <stddef.h>
#include <stdint.h>

#include "config.h"
#include "fastmath.h"
#include "geometry/intersect.h"
#include "geometry/prism.h"
#include "geometry/types.h"
#include "kernels/dither.h"
#include "kernels/gamma.h"
#include "kernels/grain.h"
#include "kernels/kernel.h"
#include "kernels/vignette.h"
#include "pipeline.h"
#include "scene.h"

#define WASM_EXPORT __attribute__((visibility("default")))

// =================================================================================================
// Application Constants
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)   // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f) // 30 degrees per hour

// =================================================================================================
// WatchfaceConfig (for JS compatibility)
// =================================================================================================

typedef struct {
  // Time
  int32_t hour; // 0-11
  float minute; // 0-59.999 (fractional for smooth animation)

  // Prism geometry and glow
  float prism_size_percent; // 10-90 (% of watch radius)
  float rainbow_spread;     // 0.0-1.0 (0 = no spread, 1 = 30 degrees)
  int32_t prism_r;          // 0-255 RGB for prism stroke
  int32_t prism_g;
  int32_t prism_b;
  float glow_width_percent; // 0.05-0.50 (% of radius)
  float glow_intensity;     // 0.1-1.0
  int32_t glow_falloff;     // 0=linear, 1=quadratic, 2=cubic, 3=exponential

  // Ray settings
  float ray_glow_width_percent; // 0.0-0.10 (% of radius)
  float ray_glow_intensity;     // 0.0-1.0
  int32_t ray_glow_falloff;     // 0=linear, 1=quadratic, 2=cubic, 3=exponential
  int32_t gradient_fill;        // 0 or 1
  int32_t palette;              // 0-4 (color palette)
  int32_t reverse_spectrum;     // 0 or 1 (album art style)

  // Marker settings
  int32_t show_markers;            // 0 or 1
  float marker_length_percent;     // 0.0-0.20
  float marker_glow_width_percent; // 0.0-0.05 (% of radius)
  float marker_glow_intensity;     // 0.0-1.0
  int32_t marker_glow_falloff;     // 0=linear, 1=quadratic, 2=cubic, 3=exponential

  // Background settings
  float grain_intensity;            // 0.0-1.0
  float grain_scale;                // DPR to scale grain size
  int32_t grain_prism_only;         // 0 or 1
  float grain_brightness_threshold; // 0.01-1.0
  int32_t vignette;                 // 0 or 1

  // Dithering settings (for e-ink display output)
  int32_t dither_enabled;      // 0 or 1
  int32_t dither_palette_mode; // 0 = IDEAL, 1 = DEVICE, 2 = SPECTRA6
  float dither_strength;       // 0.0-1.0: intensity of dither pattern (default 0.2)
  int32_t dither_kernel;       // 0 = ATKINSON, 1 = FLOYD_STEINBERG
  int32_t dither_oklab_error;  // 0 = linear RGB error diffusion, 1 = OkLab error diffusion
  float dither_bw_threshold;   // 0.0-1.0: OkLab chroma threshold for B/W-only (0.0 = disabled)
  float dither_chroma_weight;  // 0.5-4.0: weight for hue/chroma vs lightness (default 1.0)

  // Debug output (written by render, read by JS)
  float entry_u; // Parametric position of entry point on prism edge (0-1)
  float exit_u;  // Parametric position of exit point on prism edge (0-1)

} WatchfaceConfig;

// =================================================================================================
// Static State
// =================================================================================================

static WatchfaceConfig config;
static Scene scene;
static int scene_initialized = 0;
static int last_width = 0;
static int last_height = 0;

// Dither cache (static allocation for max supported dimensions)
#define MAX_DITHER_WIDTH 5120
#define MAX_DITHER_COLORS 16
DITHER_CACHE_STATIC(dither_cache, MAX_DITHER_COLORS, MAX_DITHER_WIDTH);

// =================================================================================================
// WASM Exports
// =================================================================================================

// NOLINTNEXTLINE(bugprone-reserved-identifier,readability-identifier-naming)
extern unsigned char __heap_base; // First byte after static data (provided by the linker)

// Get the address where it's safe to allocate
WASM_EXPORT void *get_heap_base(void) { return &__heap_base; }

// Get pointer to the config struct (returns byte offset into memory.buffer)
WASM_EXPORT WatchfaceConfig *get_config(void) { return &config; }

// =================================================================================================
// Main Render Function
// =================================================================================================

WASM_EXPORT void render_watchface(float *float_fb, uint8_t *fb, int width, int height) {
  // Re-initialize scene if dimensions changed
  if (!scene_initialized || width != last_width || height != last_height) {
    scene_init(&scene, width, height);
    scene_initialized = 1;
    last_width = width;
    last_height = height;
  }

  // Calculate watch geometry for debug output
  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (width < height ? (float)width : (float)height) / 2.0f - 1.0f;

  // -------------------------------------------------------------------------------------------------
  // Configure Scene from WatchfaceConfig
  // -------------------------------------------------------------------------------------------------

  // Time
  scene_set_time(&scene, config.hour, config.minute);

  // Prism configuration
  PrismConfig prism_cfg = {.size = config.prism_size_percent / 100.0f,
                           .rainbow_spread = config.rainbow_spread,
                           .blue_tint = 0.0f,
                           .gray = 0.5f};
  scene_set_prism_config(&scene, &prism_cfg);

  // Glow configuration
  GlowConfig glow_cfg = {.r = config.prism_r,
                         .g = config.prism_g,
                         .b = config.prism_b,
                         .width = config.glow_width_percent,
                         .intensity = config.glow_intensity,
                         .falloff = (FalloffType)config.glow_falloff};
  scene_set_glow_config(&scene, &glow_cfg);

  // Ray configuration
  RayConfig ray_cfg = {.glow_width = config.ray_glow_width_percent,
                       .intensity = config.ray_glow_intensity,
                       .falloff = (FalloffType)config.ray_glow_falloff,
                       .palette = config.palette,
                       .gradient_fill = config.gradient_fill,
                       .reverse = config.reverse_spectrum};
  scene_set_ray_config(&scene, &ray_cfg);

  // Marker configuration
  MarkerConfig marker_cfg = {.visible = config.show_markers,
                             .length = config.marker_length_percent,
                             .glow_width = config.marker_glow_width_percent,
                             .glow_intensity = config.marker_glow_intensity,
                             .falloff = (FalloffType)config.marker_glow_falloff};
  scene_set_marker_config(&scene, &marker_cfg);

  // -------------------------------------------------------------------------------------------------
  // Compute Debug Output (entry_u and exit_u)
  // -------------------------------------------------------------------------------------------------

  // Update prism if needed for debug calculations
  scene_update_prism(&scene);
  const Prism *prism = scene_get_prism(&scene);

  // Calculate minute position (light source on circle edge)
  float minute_angle = ANGLE_0 + (config.minute / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  // Calculate hour angle with minute interpolation
  float hour12 = (float)config.hour;
  float hour_angle = ANGLE_0 + (hour12 / 12.0f) * TAU + (config.minute / 60.0f) * HOUR_ARC;

  // Compute entry_u (where minute ray enters prism)
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);
  RayHit prism_entry = prism_find_entry(entry_x, entry_y, entry_dx, entry_dy, prism);
  config.entry_u = prism_entry.hit ? prism_entry.u : -1.0f;

  // Compute exit_u (where hour ray exits prism)
  RayHit prism_exit = prism_find_exit_from_center(cx, cy, hour_angle, prism);
  config.exit_u = prism_exit.hit ? prism_exit.u : -1.0f;

  // -------------------------------------------------------------------------------------------------
  // Render Scene to Linear Float Buffer
  // -------------------------------------------------------------------------------------------------

  scene_render_linear(&scene, float_fb);

  // -------------------------------------------------------------------------------------------------
  // Post-Processing Pipeline
  // -------------------------------------------------------------------------------------------------

  Pipeline pipeline;
  pipeline_init(&pipeline);

  // Gamma correction (linear -> sRGB)
  pipeline_add_kernel(&pipeline, &KERNEL_GAMMA, (void *)0, (void *)0);

  // Grain (in sRGB space)
  GrainConfig grain_cfg = {.intensity = config.grain_intensity,
                           .scale = config.grain_scale,
                           .threshold = config.grain_brightness_threshold,
                           .prism_only = config.grain_prism_only};

  // Collect prism vertices for grain geometry
  float prism_verts[6];
  for (size_t i = 0; i < 3; i++) {
    prism_get_vertex(prism, (int)i, &prism_verts[i * 2], &prism_verts[i * 2 + 1]);
  }

  GrainGeometry grain_geom = {.cx = cx,
                              .cy = cy,
                              .radius = radius,
                              .prism_vertices = config.grain_prism_only ? prism_verts : (void *)0};

  if (config.grain_intensity > 0.0f) {
    pipeline_add_kernel(&pipeline, &KERNEL_GRAIN, &grain_cfg, &grain_geom);
  }

  // Vignette (in sRGB space)
  VignetteConfig vignette_cfg = {
      .enabled = config.vignette,
      .strength = 0.4f,            // Default 40% darkening at corners
      .background = 35.0f / 255.0f // Grey level ~0.137
  };

  VignetteGeometry vignette_geom = {.cx = cx, .cy = cy, .radius = radius};

  if (config.vignette) {
    pipeline_add_kernel(&pipeline, &KERNEL_VIGNETTE, &vignette_cfg, &vignette_geom);
  }

  // Execute pipeline
  pipeline_execute(&pipeline, float_fb, width, height);

  // -------------------------------------------------------------------------------------------------
  // Final Output: Dithering or Direct Conversion
  // -------------------------------------------------------------------------------------------------

  if (config.dither_enabled) {
    // Select palette based on mode
    const DitherRGB *palette;
    int palette_count = 6;

    switch (config.dither_palette_mode) {
    case 0: // IDEAL
      palette = DITHER_PALETTE_IDEAL;
      break;
    case 1: // DEVICE
      palette = DITHER_PALETTE_DEVICE;
      break;
    case 2: // SPECTRA6
      palette = DITHER_PALETTE_SPECTRA6;
      break;
    default:
      palette = DITHER_PALETTE_IDEAL;
      break;
    }

    // Configure dither kernel
    DitherConfig dither_cfg = {.palette = palette,
                               .palette_count = palette_count,
                               .bw_black_idx = 0, // Black is index 0 in all palettes
                               .bw_white_idx = 1, // White is index 1 in all palettes
                               .algorithm = (DitherAlgorithm)config.dither_kernel,
                               .strength = config.dither_strength,
                               .oklab_error = config.dither_oklab_error,
                               .preserve_alpha = 1,
                               .bw_threshold = config.dither_bw_threshold,
                               .chroma_weight = config.dither_chroma_weight};

    // Apply dithering (float -> uint8)
    kernel_dither_apply(float_fb, fb, width, height, &dither_cfg, &dither_cache);
  } else {
    // Direct conversion (sRGB float -> sRGB uint8)
    // The pipeline already applied gamma, so float_fb is in sRGB space
    int total_pixels = width * height;
    for (int i = 0; i < total_pixels; i++) {
      int idx = i * 4;
      // Clamp and convert
      float r = float_fb[idx + 0];
      float g = float_fb[idx + 1];
      float b = float_fb[idx + 2];
      float a = float_fb[idx + 3];

      // Clamp to [0, 1]
      if (r < 0.0f)
        r = 0.0f;
      else if (r > 1.0f)
        r = 1.0f;
      if (g < 0.0f)
        g = 0.0f;
      else if (g > 1.0f)
        g = 1.0f;
      if (b < 0.0f)
        b = 0.0f;
      else if (b > 1.0f)
        b = 1.0f;
      if (a < 0.0f)
        a = 0.0f;
      else if (a > 1.0f)
        a = 1.0f;

      // Convert to uint8
      fb[idx + 0] = (uint8_t)(r * 255.0f + 0.5f);
      fb[idx + 1] = (uint8_t)(g * 255.0f + 0.5f);
      fb[idx + 2] = (uint8_t)(b * 255.0f + 0.5f);
      fb[idx + 3] = (uint8_t)(a * 255.0f + 0.5f);
    }
  }
}
