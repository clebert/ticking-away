#pragma once

// =================================================================================================
// Gradient Layer
// =================================================================================================
// Renders smooth rainbow gradient fills using OkLab color space interpolation.
// This layer fills the area between rainbow rays with perceptually uniform color gradients.
//
// The gradient layer is typically rendered by the rays layer when gradient_fill is enabled,
// but the functions are exposed here for reuse and testing.
//
// Gradient modes:
//   EXTERNAL: Fills inside the watch circle but outside the prism (rainbow fan effect)
//   INTERNAL: Fills only inside the prism (refracted light effect)

#include "geometry/types.h"
#include "layers/layer.h"

// -------------------------------------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------------------------------------

#define GRADIENT_NUM_BANDS 7 // Number of color bands in rainbow

// Edge margin factor for extending gradient beyond visible rays into IR/UV zones
// With centered band spacing, rays span (N-1)/N of the gradient
#define GRADIENT_EDGE_MARGIN_FACTOR (0.5f / (float)(GRADIENT_NUM_BANDS - 1))

// -------------------------------------------------------------------------------------------------
// Types
// -------------------------------------------------------------------------------------------------

// Gradient fill mode
typedef enum {
  GRADIENT_MODE_EXTERNAL, // Inside circle, outside prism (rainbow fan)
  GRADIENT_MODE_INTERNAL  // Inside prism only
} GradientMode;

// Linear RGB color (0.0-1.0 range)
typedef struct {
  float r, g, b;
} GradientRGBLinear;

// OkLab color for perceptually uniform interpolation
typedef struct {
  float L, a, b;
} GradientOkLab;

// Palette cache for efficient color lookups
typedef struct {
  int palette;                                  // Current palette index
  int initialized;                              // Whether cache is valid
  GradientRGBLinear linear[GRADIENT_NUM_BANDS]; // Linear RGB
  GradientOkLab oklab[GRADIENT_NUM_BANDS];      // OkLab for interpolation
} GradientPaletteCache;

// Macro for stack-allocating an uninitialized palette cache
#define GRADIENT_PALETTE_CACHE_STATIC(name)                                                        \
  GradientPaletteCache name = {.palette = -1, .initialized = 0}

// -------------------------------------------------------------------------------------------------
// Palette Management
// -------------------------------------------------------------------------------------------------

// Initialize palette cache for a given palette index.
// No-op if already initialized with the same palette.
void gradient_init_palette_cache(GradientPaletteCache *cache, int palette);

// Interpolate rainbow color at position t using OkLab.
// t=0 is red, t=1 is violet, extrapolates beyond for IR/UV zones.
GradientRGBLinear gradient_interpolate_color(const GradientPaletteCache *cache, float t);

// -------------------------------------------------------------------------------------------------
// Gradient Fill Functions
// -------------------------------------------------------------------------------------------------

// Draw continuous gradient fill with band-based color interpolation.
//
// Parameters:
//   fb: float RGBA framebuffer (width * height * 4)
//   width, height: framebuffer dimensions
//   mode: EXTERNAL (outside prism) or INTERNAL (inside prism)
//   origin_x, origin_y: point from which angles are measured
//   cx, cy, radius: circle geometry (only used for EXTERNAL mode)
//   angle_start, angle_end: angular bounds of gradient (radians)
//   prism: prism geometry for clipping
//   intensity: brightness multiplier
//   reverse_spectrum: if true, reverse color order (album art style)
//   cache: palette cache for color lookups
void gradient_draw_continuous(float *fb, int width, int height, GradientMode mode, float origin_x,
                              float origin_y, float cx, float cy, float radius, float angle_start,
                              float angle_end, const Prism *prism, float intensity,
                              int reverse_spectrum, const GradientPaletteCache *cache);

// -------------------------------------------------------------------------------------------------
// Layer Interface
// -------------------------------------------------------------------------------------------------
// Note: The gradient layer is typically rendered as part of the rays layer when gradient_fill
// is enabled, since it requires ray path computation. The layer interface is provided for
// testing and potential standalone use.

// Layer descriptor
extern const Layer LAYER_GRADIENT;
