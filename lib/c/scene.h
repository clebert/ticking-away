#pragma once

// =================================================================================================
// Scene Abstraction
// =================================================================================================
// High-level API for composing and rendering the watchface scene. The Scene struct holds all
// state needed to render a complete frame: geometry, time, and layer configurations.
//
// Memory model:
//   - Scene is stack-allocated by the caller (no heap allocation)
//   - Framebuffer is owned by the caller and passed to render functions
//   - Config structs are copied into the Scene (caller can free after set_*() calls)
//   - No scene_destroy() needed - caller owns the stack memory
//
// Usage:
//   Scene scene;
//   scene_init(&scene, 400, 400);
//   scene_set_time(&scene, 3, 15.0f);           // 3:15
//   scene_set_prism_config(&scene, &prism_cfg);
//   scene_set_ray_config(&scene, &ray_cfg);
//   scene_render_linear(&scene, framebuffer);   // Render to linear float buffer

#include "config.h"
#include "geometry/types.h"
#include "layers/gradient.h"
#include "layers/rays.h"

// -------------------------------------------------------------------------------------------------
// Scene Struct
// -------------------------------------------------------------------------------------------------
// Stack-allocatable struct holding all scene state. Callers allocate this on the stack or
// as a static variable.

typedef struct {
  // Dimensions
  int width;
  int height;

  // Watch circle geometry (computed from dimensions)
  float cx;     // Center X
  float cy;     // Center Y
  float radius; // Radius in pixels

  // Time (stored as minutes for easy computation)
  float time_minutes; // 0.0-720.0 for 12-hour display (wraps at 720)

  // Prism geometry (computed from config)
  Prism prism;

  // Configuration (copied from caller)
  PrismConfig prism_config;
  GlowConfig glow_config;
  RayConfig ray_config;
  MarkerConfig marker_config;

  // Internal state flags
  int prism_dirty; // 1 if prism needs recomputing

  // Palette caches (owned by scene, no global state)
  RaysPaletteCache rays_palette_cache;
  GradientPaletteCache gradient_palette_cache;
} Scene;

// -------------------------------------------------------------------------------------------------
// Initialization
// -------------------------------------------------------------------------------------------------

// Initialize a scene with the given dimensions.
// Sets up default configurations and computes circle geometry.
// The scene is ready to render after this call with default settings.
//
// Parameters:
//   scene: Pointer to caller-owned Scene struct
//   width: Framebuffer width in pixels
//   height: Framebuffer height in pixels
void scene_init(Scene *scene, int width, int height);

// -------------------------------------------------------------------------------------------------
// Time Configuration
// -------------------------------------------------------------------------------------------------

// Set the time to display.
// Time is in 12-hour format. Hours outside [0, 11] are wrapped.
// Minutes outside [0, 60) are wrapped.
//
// Parameters:
//   scene: Scene to configure
//   hour: Hour (0-11, wraps for values outside this range)
//   minute: Minute with fractional seconds (0.0-59.999...)
void scene_set_time(Scene *scene, int hour, float minute);

// Set time directly in minutes (0.0-720.0 range).
// Useful when time is already computed.
//
// Parameters:
//   scene: Scene to configure
//   minutes: Total minutes (hour * 60 + minute), wraps at 720
void scene_set_time_minutes(Scene *scene, float minutes);

// -------------------------------------------------------------------------------------------------
// Layer Configuration
// -------------------------------------------------------------------------------------------------

// Set prism configuration.
// Marks the prism as dirty so it will be recomputed on next render.
//
// Parameters:
//   scene: Scene to configure
//   config: Prism configuration (copied, caller can free after call)
void scene_set_prism_config(Scene *scene, const PrismConfig *config);

// Set prism glow configuration.
//
// Parameters:
//   scene: Scene to configure
//   config: Glow configuration (copied, caller can free after call)
void scene_set_glow_config(Scene *scene, const GlowConfig *config);

// Set ray configuration.
// Changes to palette invalidate the palette cache.
//
// Parameters:
//   scene: Scene to configure
//   config: Ray configuration (copied, caller can free after call)
void scene_set_ray_config(Scene *scene, const RayConfig *config);

// Set marker configuration.
//
// Parameters:
//   scene: Scene to configure
//   config: Marker configuration (copied, caller can free after call)
void scene_set_marker_config(Scene *scene, const MarkerConfig *config);

// -------------------------------------------------------------------------------------------------
// Rendering
// -------------------------------------------------------------------------------------------------

// Render the complete scene to a linear float framebuffer.
// The framebuffer should be pre-allocated with width * height * 4 floats (RGBA).
// Output is in linear color space - caller should apply gamma correction and dithering.
//
// Render order:
//   1. Background (black circle with alpha)
//   2. Rays (white entry + colored exit rays, with optional gradient fill)
//   3. Prism glow (inner edge glow effect)
//   4. Markers (12 hour markers)
//
// Parameters:
//   scene: Scene to render
//   fb: Caller-owned float RGBA buffer (width * height * 4 floats)
void scene_render_linear(Scene *scene, float *fb);

// -------------------------------------------------------------------------------------------------
// Utility Functions
// -------------------------------------------------------------------------------------------------

// Recompute prism geometry from current configuration.
// Called automatically by render if prism_dirty is set.
// Can be called manually if you want to query prism geometry before rendering.
//
// Parameters:
//   scene: Scene with prism_config set
void scene_update_prism(Scene *scene);

// Get the current prism geometry.
// Returns a pointer to the internal Prism struct (valid until scene is destroyed).
//
// Parameters:
//   scene: Scene with prism geometry computed
// Returns:
//   Pointer to the prism geometry (read-only, owned by scene)
const Prism *scene_get_prism(const Scene *scene);
