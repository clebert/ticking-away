#pragma once

// =================================================================================================
// Layer Abstraction
// =================================================================================================
// Defines the interface for composable render layers. Each layer renders a specific visual
// element (background, rays, gradient, prism glow, markers) to the framebuffer.
//
// Layers receive a shared RenderContext with all the state they need. This allows layers
// to be composed in any order and makes dependencies explicit.

#include "config.h"
#include "geometry/types.h"

// -------------------------------------------------------------------------------------------------
// Render Context
// -------------------------------------------------------------------------------------------------
// Shared state passed to all layers. Contains the framebuffer, dimensions, and all configuration
// needed for rendering. Layers read from this context but should not modify it (except the
// framebuffer itself).

typedef struct {
  // Framebuffer
  float *fb;  // RGBA float buffer (linear color space), owned by caller
  int width;  // Framebuffer width in pixels
  int height; // Framebuffer height in pixels

  // Watch circle geometry
  float cx;     // Circle center X
  float cy;     // Circle center Y
  float radius; // Circle radius in pixels

  // Prism geometry
  const Prism *prism;

  // Time
  float time_minutes; // Time in minutes: 0.0-720.0 for 12-hour display
                      // e.g., 3:15 = 3*60 + 15 = 195.0
                      // Wraps at 720 (12 hours)

  // Layer configurations (const pointers, may be NULL if layer not used)
  const PrismConfig *prism_config;
  const GlowConfig *glow_config;
  const RayConfig *ray_config;
  const MarkerConfig *marker_config;
} RenderContext;

// -------------------------------------------------------------------------------------------------
// Layer Interface
// -------------------------------------------------------------------------------------------------
// Function signature for layer render functions. Each layer receives the full context and
// renders its contribution to the framebuffer.

typedef void (*LayerRenderFn)(const RenderContext *ctx);

// Layer descriptor with metadata and render function.
// Layers can be registered and composed into a scene.

typedef struct {
  const char *name;     // Human-readable layer name (for debugging)
  LayerRenderFn render; // Render function
} Layer;

// -------------------------------------------------------------------------------------------------
// Convenience macros for layer definition
// -------------------------------------------------------------------------------------------------

// Define a layer with name and render function
#define LAYER_DEFINE(layer_name, render_fn) static const Layer layer_name = {#layer_name, render_fn}
