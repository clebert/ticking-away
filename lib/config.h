#pragma once

// =================================================================================================
// Configuration Structs
// =================================================================================================
// Focused configuration types that replace the monolithic WatchfaceConfig.
// Each struct groups related settings for a specific aspect of rendering.

#include "effects/effect.h"
#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Prism Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  float size;           // Size as fraction of watch radius (0.1 - 0.9)
  float rainbow_spread; // 0.0 - 1.0 (0 = no spread, 1 = 30 degrees)
} PrismConfig;

// -------------------------------------------------------------------------------------------------
// Prism Glow Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  int32_t r, g, b;     // RGB color for prism stroke (0-255)
  float width;         // Glow width as fraction of radius (0.05 - 0.50)
  float intensity;     // Glow intensity (0.1 - 1.0)
  FalloffType falloff; // Falloff curve type
} GlowConfig;

// -------------------------------------------------------------------------------------------------
// Ray Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  float glow_width;      // Glow width as fraction of radius (0.0 - 0.10)
  float intensity;       // Glow intensity (0.0 - 1.0)
  FalloffType falloff;   // Falloff curve type
  int32_t palette;       // Color palette index (0-4)
  int32_t gradient_fill; // Fill gradient between rays (0 or 1)
  int32_t reverse;       // Reverse spectrum (album art style, 0 or 1)
} RayConfig;

// -------------------------------------------------------------------------------------------------
// Marker Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  int32_t visible;      // Show markers (0 or 1)
  float length;         // Length as fraction of radius (0.0 - 0.20)
  float glow_width;     // Glow width as fraction of radius (0.0 - 0.05)
  float glow_intensity; // Glow intensity (0.0 - 1.0)
  FalloffType falloff;  // Falloff curve type
} MarkerConfig;

// -------------------------------------------------------------------------------------------------
// Grain Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  float intensity;    // Grain intensity (0.0 - 1.0)
  float scale;        // DPR to scale grain size
  float threshold;    // Brightness threshold (0.01 - 1.0)
  int32_t prism_only; // Apply grain only inside prism (0 or 1)
} GrainConfig;

// -------------------------------------------------------------------------------------------------
// Dither Configuration
// -------------------------------------------------------------------------------------------------

typedef enum {
  DITHER_MODE_IDEAL = 0,           // Ideal spectrum colors
  DITHER_MODE_SPECTRA6_INKY = 1,   // Spectra 6 from Pimoroni Inky library
  DITHER_MODE_SPECTRA6_EPDOPT = 2, // Spectra 6 from EDP Optimize (measured)
} DitherPaletteMode;

typedef enum {
  DITHER_TYPE_ERROR = 0,  // Error diffusion (Atkinson, Floyd-Steinberg)
  DITHER_TYPE_ORDERED = 1 // Ordered dithering (Bayer matrices)
} DitherType;

typedef enum {
  DITHER_ALGORITHM_ATKINSON = 0,
  DITHER_ALGORITHM_FLOYD_STEINBERG = 1
} DitherAlgorithmType;

typedef enum {
  DITHER_ORDERED_BAYER_2X2 = 0,
  DITHER_ORDERED_BAYER_4X4 = 1,
  DITHER_ORDERED_BAYER_8X8 = 2
} DitherOrderedMatrixType;

typedef struct {
  int32_t enabled;        // Enable dithering (0 or 1)
  DitherType type;        // Error diffusion or ordered
  DitherPaletteMode mode; // Palette mode
  // Error diffusion params
  float strength;                // Dither pattern intensity (0.0 - 1.0)
  DitherAlgorithmType algorithm; // Error diffusion algorithm
  int32_t oklab_error;           // Use OkLab error diffusion (0 or 1)
  // Ordered params
  DitherOrderedMatrixType ordered_matrix; // Bayer matrix size
  float spread;                           // Threshold spread (0.0 - 1.0)
  // Shared
  float chroma_weight; // Weight for hue/chroma vs lightness (0.5 - 4.0)
} SceneDitherConfig;

// -------------------------------------------------------------------------------------------------
// Vignette Configuration
// -------------------------------------------------------------------------------------------------

typedef struct {
  int32_t enabled;  // Enable vignette (0 or 1)
  float strength;   // Max darkening at corners (0.0-1.0, default 0.4 = 40%)
  float background; // Grey level in sRGB space (0.0-1.0, default ~0.137 = 35/255)
} VignetteConfig;
