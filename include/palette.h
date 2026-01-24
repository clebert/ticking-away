#pragma once

#include "color.h"

// =================================================================================================
// Rainbow Colors (7 perceptually balanced bands)
// =================================================================================================

// 7 bands derived from OkLCH with equal hue spacing for perceptual uniformity
#define NUM_BANDS 7

// Color palette presets for rainbow bands
typedef enum {
  PALETTE_OKLCH_BALANCED = 0,  // Current: equal OkLCH hue spacing (friendly)
  PALETTE_SATURATED = 1,       // Higher saturation, more vivid
  PALETTE_SPECTRAL = 2,        // Closer to physical spectrum
  PALETTE_NEON = 3,            // Electric/neon look
  PALETTE_MUTED = 4,           // Desaturated, cinematic
  PALETTE_EINK_PURE = 5,       // Pure e-ink colors only (R,Y,G,B) - minimal dithering
  PALETTE_EINK_DITHER = 6,     // Optimized for e-ink dithering, skip violet
  PALETTE_EINK_FULL = 7,       // Full spectrum, violet biased toward blue
  PALETTE_ALBUM_COVER = 8,     // Dark Side aesthetic - deep saturated edges
  PALETTE_SPECTRA6 = 9,        // Optimized for Spectra 6 e-ink display
  PALETTE_COUNT
} ColorPalette;

// Palette definitions: [palette][band][rgb] in sRGB
static const uint8_t PALETTE_COLORS[PALETTE_COUNT][NUM_BANDS][3] = {
  // PALETTE_OKLCH_BALANCED (friendly, even OkLCH hue spacing)
  {
    {255,  64,  64},  // Red      (OkLCH hue ~30°)
    {255, 160,   0},  // Orange   (OkLCH hue ~70°)
    {220, 220,   0},  // Yellow   (OkLCH hue ~110°)
    {  0, 200,  80},  // Green    (OkLCH hue ~150°)
    {  0, 180, 220},  // Cyan     (OkLCH hue ~195°)
    { 80, 100, 255},  // Blue     (OkLCH hue ~250°)
    {180,  80, 255}   // Violet   (OkLCH hue ~300°)
  },
  // PALETTE_SATURATED (vivid, punchy)
  {
    {255,   0,   0},  // Pure red
    {255, 128,   0},  // Vivid orange
    {255, 255,   0},  // Pure yellow
    {  0, 255,   0},  // Pure green
    {  0, 255, 255},  // Pure cyan
    {  0,   0, 255},  // Pure blue
    {128,   0, 255}   // Vivid violet
  },
  // PALETTE_SPECTRAL (closer to physical spectrum)
  {
    {255,   0,   0},  // 700nm Red
    {255, 127,   0},  // 620nm Orange
    {255, 255,   0},  // 580nm Yellow
    {  0, 255,   0},  // 530nm Green
    {  0, 127, 255},  // 480nm Cyan-blue
    {  0,   0, 255},  // 450nm Blue
    {139,   0, 255}   // 400nm Violet
  },
  // PALETTE_NEON (electric, oversaturated feel)
  {
    {255,  20,  80},  // Hot pink-red
    {255, 100,   0},  // Neon orange
    {200, 255,   0},  // Lime yellow
    {  0, 255, 100},  // Electric green
    {  0, 200, 255},  // Cyan
    { 50,  50, 255},  // Electric blue
    {200,   0, 255}   // Neon purple
  },
  // PALETTE_MUTED (desaturated, cinematic)
  {
    {200,  80,  80},  // Dusty red
    {200, 140,  70},  // Muted orange
    {180, 180,  80},  // Olive yellow
    { 70, 160, 100},  // Sage green
    { 80, 150, 180},  // Steel cyan
    {100, 110, 200},  // Dusty blue
    {150, 100, 200}   // Muted violet
  },
  // PALETTE_EINK_PURE (pure e-ink colors only - minimal dithering)
  // Uses only R,Y,G,B - colors that map directly to e-ink palette
  {
    {255,   0,   0},  // Red
    {255, 255,   0},  // Yellow (skip orange)
    {255, 255,   0},  // Yellow
    {  0, 255,   0},  // Green
    {  0, 255,   0},  // Green
    {  0,   0, 255},  // Blue
    {  0,   0, 255}   // Blue (skip violet)
  },
  // PALETTE_EINK_DITHER (optimized for e-ink dithering)
  // Good dither pairs: R+Y for orange, G+B for cyan, skip violet
  {
    {255,   0,   0},  // Red - pure
    {255, 176,   0},  // Orange - R+Y dither (biased yellow)
    {255, 255,   0},  // Yellow - pure
    {  0, 255,   0},  // Green - pure
    {  0, 160, 255},  // Sky blue - G+B dither (biased blue)
    {  0,   0, 255},  // Blue - pure
    {  0,   0, 255}   // Blue (no violet - avoids ugly B+R)
  },
  // PALETTE_EINK_FULL (full spectrum, violet optimized)
  // Violet biased heavily toward blue to avoid magenta dithering
  {
    {255,   0,   0},  // Red
    {255, 160,   0},  // Orange
    {255, 255,   0},  // Yellow
    {  0, 255,   0},  // Green
    {  0, 180, 220},  // Teal-cyan
    {  0,   0, 255},  // Blue
    { 40,   0, 255}   // Violet (almost pure blue, minimal R)
  },
  // PALETTE_ALBUM_COVER (Dark Side of the Moon aesthetic)
  // Deep saturated edges using black dithering for depth
  {
    {200,   0,   0},  // Deep red (dithers R+Black)
    {255, 140,   0},  // Rich orange
    {255, 255,   0},  // Bright yellow
    {  0, 220,   0},  // Vivid green
    {  0, 100, 255},  // Deep cyan-blue
    {  0,   0, 200},  // Deep blue (dithers B+Black)
    { 60,   0, 180}   // Deep violet
  },
  // PALETTE_SPECTRA6 (optimized for Spectra 6 e-ink display)
  // Colors close to actual Spectra 6 hardware capabilities for smoother dithering
  // Spectra 6: Black #191E21, White #E8E8E8, Yellow #EFDE44, Red #B21318, Blue #2157BA, Green #125F20
  {
    {178,  19,  24},  // Red (Spectra 6 red)
    {220, 130,  35},  // Orange (balanced, gives yellow more room)
    {240, 220,  60},  // Yellow (bright, close to Spectra 6)
    { 70, 145,  55},  // Green (brighter, dithers G+Y/W for luminance)
    {  0, 140, 200},  // Cyan (blue-biased, gives green more room)
    { 30,  70, 160},  // Blue (toned down, gives green more room)
    {100,  30, 160}   // Violet (dithers Blue+Red for purple)
  }
};

// Edge margin factor for extending gradient beyond visible rays into IR/UV zones
// With centered band spacing, rays span (N-1)/N of the gradient; this extends each edge by 0.5/N
#define EDGE_MARGIN_FACTOR (0.5f / (float)(NUM_BANDS - 1))

// =================================================================================================
// Band Color Storage
// =================================================================================================

// Precomputed linear RGB colors for each band
static RGB_Linear BAND_COLORS_LINEAR[NUM_BANDS];
// Precomputed OkLab colors for perceptually uniform gradient interpolation
static OkLab BAND_COLORS_OKLAB[NUM_BANDS];
static ColorPalette current_palette = PALETTE_OKLCH_BALANCED;
static int band_colors_initialized = 0;

// Initialize rainbow colors from selected palette.
// Precomputes both linear RGB and OkLab representations for efficient blending.
// Reinitializes if palette changes.
static void init_band_colors(ColorPalette palette) {
  // Skip if already initialized with same palette
  if (band_colors_initialized && current_palette == palette) return;

  for (int i = 0; i < NUM_BANDS; i++) {
    BAND_COLORS_LINEAR[i].r = srgb_to_linear(PALETTE_COLORS[palette][i][0]);
    BAND_COLORS_LINEAR[i].g = srgb_to_linear(PALETTE_COLORS[palette][i][1]);
    BAND_COLORS_LINEAR[i].b = srgb_to_linear(PALETTE_COLORS[palette][i][2]);

    // Precompute OkLab for gradient interpolation
    BAND_COLORS_OKLAB[i] = linear_to_oklab(
      BAND_COLORS_LINEAR[i].r,
      BAND_COLORS_LINEAR[i].g,
      BAND_COLORS_LINEAR[i].b
    );
  }

  current_palette = palette;
  band_colors_initialized = 1;
}
