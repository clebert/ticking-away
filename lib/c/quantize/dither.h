#pragma once

// =================================================================================================
// Dither Common Types and Utilities
// =================================================================================================
// Shared types, palettes, and color conversion functions used by all dithering algorithms.
//
// This header provides:
// - Color types (DitherRGB, DitherOkLab, DitherLinearRGB)
// - Standard palettes (IDEAL, SPECTRA6_INKY, SPECTRA6_EPDOPT)
// - Color space conversions (sRGB ↔ linear, linear → OkLab)
// - OkLab distance functions for perceptually accurate color matching
//
// Algorithm-specific APIs are in separate headers:
// - dither_error.h: Error diffusion (Atkinson, Floyd-Steinberg)
// - dither_ordered.h: Ordered dithering (Bayer, etc.)

#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Palette RGB Type
// -------------------------------------------------------------------------------------------------

typedef struct {
  uint8_t r, g, b;
} DitherRGB;

// -------------------------------------------------------------------------------------------------
// OkLab Color Type
// -------------------------------------------------------------------------------------------------
// OkLab is a perceptually uniform color space, ideal for color matching.

typedef struct {
  float L, a, b;
} DitherOkLab;

// -------------------------------------------------------------------------------------------------
// Linear RGB Type
// -------------------------------------------------------------------------------------------------

typedef struct {
  float r, g, b;
} DitherLinearRGB;

// -------------------------------------------------------------------------------------------------
// Standard Palettes (convenience constants)
// -------------------------------------------------------------------------------------------------
// These are provided for convenience. Callers can also provide custom palettes.

// Pure RGB palette (ideal target colors) - 6 colors
extern const DitherRGB DITHER_PALETTE_IDEAL[];
enum { DITHER_PALETTE_IDEAL_COUNT = 6 };

// Spectra 6 palette from Pimoroni Inky library (Inky Impression 13.3") - 6 colors
extern const DitherRGB DITHER_PALETTE_SPECTRA6_INKY[];
enum { DITHER_PALETTE_SPECTRA6_INKY_COUNT = 6 };

// Spectra 6 palette from epdoptimize (measured values) - 6 colors
extern const DitherRGB DITHER_PALETTE_SPECTRA6_EPDOPT[];
enum { DITHER_PALETTE_SPECTRA6_EPDOPT_COUNT = 6 };

// Spectra 6 palette from TRMNL firmware - 6 colors
extern const DitherRGB DITHER_PALETTE_SPECTRA6_TRMNL[];
enum { DITHER_PALETTE_SPECTRA6_TRMNL_COUNT = 6 };

// -------------------------------------------------------------------------------------------------
// Color Space Conversion Functions
// -------------------------------------------------------------------------------------------------

// Convert sRGB (0-255) to linear (0.0-1.0)
float dither_srgb_to_linear(uint8_t srgb);

// Convert linear RGB to OkLab
DitherOkLab dither_linear_to_oklab(float r, float g, float b);

// -------------------------------------------------------------------------------------------------
// OkLab Utility Functions
// -------------------------------------------------------------------------------------------------

// Compute OkLab chroma (saturation metric)
float dither_oklab_chroma(DitherOkLab color);

// OkLab weighted distance squared
// chroma_weight = 1.0: L weighted 2x (default, good for general images)
// chroma_weight = 2.0: Equal L and chroma weighting (better for rainbows)
// chroma_weight = 4.0: Chroma weighted 2x (strongly prioritizes hue matching)
float dither_oklab_distance_sq(DitherOkLab a, DitherOkLab b, float chroma_weight);

// Find closest palette color index using OkLab distance
int dither_find_closest_color(DitherOkLab color, const DitherOkLab *palette, int palette_count,
                              float chroma_weight);
