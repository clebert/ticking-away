// =================================================================================================
// WASM Module
// =================================================================================================
// Uses the modular Scene + Pipeline APIs instead of the monolithic render_watchface_scene().

#include "config.h"
#include "effects/gamma.h"
#include "effects/grain.h"
#include "effects/vignette.h"
#include "fastmath.h"
#include "geometry/intersect.h"
#include "geometry/prism.h"
#include "geometry/types.h"
#include "pipeline.h"
#include "quantize/direct.h"
#include "quantize/dither.h"
#include "quantize/dither_error.h"
#include "quantize/dither_ordered.h"
#include "scene.h"
#include <stddef.h>
#include <stdint.h>

#define WASM_EXPORT __attribute__((visibility("default")))

// =================================================================================================
// Application Constants
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)   // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f) // 30 degrees per hour

// =================================================================================================
// WatchfaceConfig (for JS compatibility)
// =================================================================================================
// Embeds the library config types directly so JS can set values without C remapping.
// Field layout must match the TypeScript definition in src/config.ts.

typedef struct {
  // Time
  int32_t hour; // 0-11
  float minute; // 0-59.999 (fractional for smooth animation)

  // Embedded config structs (from lib/config.h)
  PrismConfig prism;
  GlowConfig glow;
  RayConfig ray;
  MarkerConfig marker;
  GrainConfig grain;
  VignetteConfig vignette;
  SceneDitherConfig dither;

  // Debug output (written by render, read by JS)
  float entry_u; // Parametric position of entry point on prism edge (0-1)
  float exit_u;  // Parametric position of exit point on prism edge (0-1)

} WatchfaceConfig;

// =================================================================================================
// Static State
// =================================================================================================

static WatchfaceConfig config;
static Scene scene;
static bool scene_initialized = false;
static int last_width = 0;
static int last_height = 0;

// Dither caches (static allocation for max supported dimensions)
enum { MAX_DITHER_WIDTH = 5120, MAX_DITHER_COLORS = 16 };
DITHER_ERROR_CACHE_STATIC(dither_error_cache, MAX_DITHER_COLORS, MAX_DITHER_WIDTH);
DITHER_ORDERED_CACHE_STATIC(dither_ordered_cache, MAX_DITHER_COLORS);

// =================================================================================================
// WASM Exports
// =================================================================================================

// NOLINTBEGIN(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming)
extern unsigned char __heap_base; // First byte after static data (provided by the linker)

// Get the address where it's safe to allocate
WASM_EXPORT void *get_heap_base(void) { return &__heap_base; }
// NOLINTEND(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming)

// Get pointer to the config struct (returns byte offset into memory.buffer)
WASM_EXPORT WatchfaceConfig *get_config(void) { return &config; }

// =================================================================================================
// Main Render Function
// =================================================================================================

WASM_EXPORT void render_watchface(float *float_fb, uint8_t *fb, int width, int height) {
  // Re-initialize scene if dimensions changed
  if (!scene_initialized || width != last_width || height != last_height) {
    scene_init(&scene, width, height);
    scene_initialized = true;
    last_width = width;
    last_height = height;
  }

  // Calculate watch geometry for debug output
  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (width < height ? (float)width : (float)height) / 2.0f;

  // -------------------------------------------------------------------------------------------------
  // Configure Scene from WatchfaceConfig (using embedded config structs directly)
  // -------------------------------------------------------------------------------------------------

  scene_set_time(&scene, config.hour, config.minute);
  scene_set_prism_config(&scene, &config.prism);
  scene_set_glow_config(&scene, &config.glow);
  scene_set_ray_config(&scene, &config.ray);
  scene_set_marker_config(&scene, &config.marker);

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
  pipeline_add_effect(&pipeline, &EFFECT_GAMMA, nullptr, (void *)0);

  // Grain (in sRGB space)
  float prism_verts[6];
  for (size_t i = 0; i < 3; i++) {
    prism_get_vertex(prism, (int)i, &prism_verts[i * 2], &prism_verts[i * 2 + 1]);
  }

  GrainGeometry grain_geom = {.cx = cx,
                              .cy = cy,
                              .radius = radius,
                              .prism_vertices = config.grain.prism_only ? prism_verts : nullptr};

  if (config.grain.intensity > 0.0f) {
    pipeline_add_effect(&pipeline, &EFFECT_GRAIN, &config.grain, &grain_geom);
  }

  // Vignette (in sRGB space)
  VignetteGeometry vignette_geom = {.cx = cx, .cy = cy, .radius = radius};

  if (config.vignette.enabled) {
    pipeline_add_effect(&pipeline, &EFFECT_VIGNETTE, &config.vignette, &vignette_geom);
  }

  // Execute pipeline
  pipeline_execute(&pipeline, float_fb, width, height);

  // -------------------------------------------------------------------------------------------------
  // Final Output: Dithering or Direct Conversion
  // -------------------------------------------------------------------------------------------------

  if (config.dither.enabled) {
    // Select palette based on mode
    const DitherRGB *palette;
    int palette_count = 6;

    switch (config.dither.mode) {
    case DITHER_MODE_IDEAL:
      palette = DITHER_PALETTE_IDEAL;
      break;
    case DITHER_MODE_SPECTRA6_INKY:
      palette = DITHER_PALETTE_SPECTRA6_INKY;
      break;
    case DITHER_MODE_SPECTRA6_EPDOPT:
      palette = DITHER_PALETTE_SPECTRA6_EPDOPT;
      break;
    default:
      palette = DITHER_PALETTE_IDEAL;
      break;
    }

    if (config.dither.type == DITHER_TYPE_ERROR) {
      // Error diffusion dithering
      DitherErrorConfig dither_cfg = {.palette = palette,
                                      .palette_count = palette_count,
                                      .algorithm = (DitherErrorAlgorithm)config.dither.algorithm,
                                      .strength = config.dither.strength,
                                      .oklab_error = config.dither.oklab_error,
                                      .chroma_weight = config.dither.chroma_weight};
      dither_error_apply(float_fb, fb, width, height, &dither_cfg, &dither_error_cache);
    } else {
      // Ordered dithering (Bayer)
      DitherOrderedConfig dither_cfg = {.palette = palette,
                                        .palette_count = palette_count,
                                        .matrix = (DitherOrderedMatrix)config.dither.ordered_matrix,
                                        .spread = config.dither.spread,
                                        .chroma_weight = config.dither.chroma_weight};
      dither_ordered_apply(float_fb, fb, width, height, &dither_cfg, &dither_ordered_cache);
    }
  } else {
    // Direct conversion (sRGB float -> sRGB uint8)
    quantize_direct_apply(float_fb, fb, width, height);
  }
}
