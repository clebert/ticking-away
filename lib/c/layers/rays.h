#pragma once

// =================================================================================================
// Rays Layer
// =================================================================================================
// Renders light rays entering the prism, refracting inside, and exiting as a rainbow.
//
// Ray structure:
//   1. Entry ray: white light from minute hand position to prism entry point
//   2. Internal path: may be direct (entry→exit) or bounced (entry→vertex→exit)
//   3. Exit rays: colored light from prism exit to circle edge (one per color band)
//
// When gradient_fill is enabled, fills the rainbow region with smooth color gradients
// instead of discrete rays.

#include "geometry/types.h"
#include "layers/layer.h"

// -------------------------------------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------------------------------------

enum { RAYS_NUM_BANDS = 7 };      // Number of color bands in rainbow
#define RAYS_MAX_SPREAD_DEG 30.0f // Maximum rainbow spread in degrees

// -------------------------------------------------------------------------------------------------
// Color Types
// -------------------------------------------------------------------------------------------------

// Linear RGB color (0.0-1.0 range)
typedef struct {
  float r, g, b;
} RaysRGBLinear;

// OkLab color for perceptually uniform interpolation
typedef struct {
  float L, a, b;
} RaysOkLab;

// -------------------------------------------------------------------------------------------------
// Color Palette Cache
// -------------------------------------------------------------------------------------------------
// Band colors are precomputed from sRGB palette values and cached in both linear RGB
// and OkLab formats. This avoids global state and allows the caller to own the cache.

typedef struct {
  int palette;                          // Current palette index (for cache invalidation)
  int initialized;                      // Whether cache is valid
  RaysRGBLinear linear[RAYS_NUM_BANDS]; // Linear RGB for additive blending
  RaysOkLab oklab[RAYS_NUM_BANDS];      // OkLab for gradient interpolation
} RaysPaletteCache;

// Macro for stack-allocating an uninitialized palette cache
#define RAYS_PALETTE_CACHE_STATIC(name) RaysPaletteCache name = {.palette = -1, .initialized = 0}

// -------------------------------------------------------------------------------------------------
// Ray Path Geometry
// -------------------------------------------------------------------------------------------------
// Precomputed geometry for all ray paths through the prism. This separates geometry
// computation from rendering, making it testable and reusable.

// A line segment with endpoints
typedef struct {
  float x0, y0; // Start point
  float x1, y1; // End point
  int valid;    // 1 if segment exists, 0 if not
} RaysSegment;

// Path for a single color band through the prism
typedef struct {
  RaysSegment internal_seg1;              // Entry to exit (or entry to bounce)
  RaysSegment internal_seg2;              // Bounce to exit (only if bounced)
  RaysSegment exit_ray;                   // Prism exit to circle edge
  float internal_exit_x, internal_exit_y; // Internal endpoint
  float prism_exit_x, prism_exit_y;       // Prism exit point
  float exit_angle;                       // Exit angle for this band
} RaysBandPath;

// Complete ray path geometry for the scene
typedef struct {
  RaysSegment entry_ray;  // Entry ray (shared by all bands)
  float entry_x, entry_y; // Prism entry point
  int entry_edge;         // Which prism edge was hit
  float entry_u;          // Parametric position along entry edge

  int needs_bounce;         // Whether rays need to bounce
  float bounce_x, bounce_y; // Bounce point coordinates

  RaysBandPath bands[RAYS_NUM_BANDS]; // Per-band paths

  int hits_prism;     // Whether entry ray hits prism
  int gradient_valid; // Whether gradient boundary data is valid

  // Gradient boundary data
  float angle_first, angle_last;
  float exit_first_x, exit_first_y;
  float exit_last_x, exit_last_y;
  float border_first_x, border_first_y;
  float border_last_x, border_last_y;
} RaysPaths;

// -------------------------------------------------------------------------------------------------
// Layer API
// -------------------------------------------------------------------------------------------------

// Render the rays layer.
//
// Required context fields:
//   fb, width, height, cx, cy, radius, prism, time_minutes, ray_config, prism_config
//
// Computes ray paths from time_minutes:
//   - Minute hand position (entry point) from minutes component
//   - Hour angle (exit direction) from hours + interpolated minutes
void layer_rays_render(const RenderContext *ctx);

// Layer descriptor for use with scene composition
extern const Layer LAYER_RAYS;

// -------------------------------------------------------------------------------------------------
// Testable Internal Functions
// -------------------------------------------------------------------------------------------------
// These functions are exposed for unit testing. Normal usage should go through the layer API.

// Initialize palette cache for a given palette index. No-op if already initialized
// with the same palette.
void rays_init_palette_cache(RaysPaletteCache *cache, int palette);

// Compute ray paths for the scene. Returns geometry without rendering.
RaysPaths rays_compute_paths(float cx, float cy, float radius, float entry_x, float entry_y,
                             float hour_angle, float rainbow_spread, const Prism *prism);

// Get band color from cache (linear RGB)
RaysRGBLinear rays_get_band_color(const RaysPaletteCache *cache, int band_idx);

// Interpolate rainbow color at position t (0=red, 1=violet, extrapolates beyond)
RaysRGBLinear rays_interpolate_color(const RaysPaletteCache *cache, float t);
