#pragma once

// =================================================================================================
// Ray Palette Types
// =================================================================================================
// Color palette identifiers for ray and gradient rendering.
// Separated into its own header to avoid circular dependencies between config.h and rays.h.

typedef enum {
  RAY_PALETTE_OKLCH_BALANCED = 0,
  RAY_PALETTE_SATURATED = 1,
  RAY_PALETTE_SPECTRAL = 2,
  RAY_PALETTE_NEON = 3,
  RAY_PALETTE_MUTED = 4,
  RAY_PALETTE_EINK_PURE = 5,
  RAY_PALETTE_EINK_DITHER = 6,
  RAY_PALETTE_EINK_FULL = 7,
  RAY_PALETTE_ALBUM_COVER = 8,
  RAY_PALETTE_SPECTRA6 = 9,
  RAY_PALETTE_COUNT = 10
} RayPalette;
