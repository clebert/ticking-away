#pragma once

#include <stdint.h>

#define DITHER_MAX_WIDTH 5120

// Dithering modes
#define DITHER_MODE_NONE 0
#define DITHER_MODE_1BIT 1
#define DITHER_MODE_2BIT 2

// Convert RGB to luminance using standard weights
static inline int luminance(int r, int g, int b) {
  return (r * 299 + g * 587 + b * 114) / 1000;
}

// Quantize luminance based on dithering mode
// 1-bit: 2 levels (black, white)
// 2-bit: 4 levels (black #000000, dark gray #555555, light gray #aaaaaa, white #ffffff)
//        https://docs.usetrmnl.com/go/diy/imagemagick-guide#h_6b95d41fbd-1
static inline int quantize_luminance(int lum, int mode) {
  if (mode == DITHER_MODE_1BIT) {
    // 1-bit: threshold at 128
    return (lum < 128) ? 0 : 255;
  } else {
    // 2-bit: 4 evenly-spaced levels (0, 85, 170, 255)
    // Thresholds at midpoints: 43, 128, 213
    if (lum < 43)       return 0;    // #000000
    else if (lum < 128) return 85;   // #555555
    else if (lum < 213) return 170;  // #aaaaaa
    else                return 255;  // #ffffff
  }
}

// Atkinson dithering - distributes only 75% of error for higher contrast
// mode: 1 = 1-bit (black/white), 2 = 2-bit (4 levels)
static inline void apply_dithering(uint8_t* fb, int width, int height, int mode) {
  if (width > DITHER_MAX_WIDTH || mode == DITHER_MODE_NONE) return;

  // Three row buffers for error diffusion (Atkinson spreads error 2 rows down)
  static int err_curr[DITHER_MAX_WIDTH];
  static int err_next1[DITHER_MAX_WIDTH];
  static int err_next2[DITHER_MAX_WIDTH];

  // Clear error buffers
  for (int i = 0; i < width; i++) {
    err_curr[i] = 0;
    err_next1[i] = 0;
    err_next2[i] = 0;
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int idx = (y * width + x) * 4;

      // Get original luminance and add accumulated error
      int old_lum = luminance(fb[idx], fb[idx + 1], fb[idx + 2]) + err_curr[x];

      // Quantize based on mode
      int new_lum = quantize_luminance(old_lum, mode);
      int error = old_lum - new_lum;
      int error_eighth = error / 8;

      fb[idx] = new_lum;
      fb[idx + 1] = new_lum;
      fb[idx + 2] = new_lum;

      // Atkinson distributes only 6/8 (75%) of the error, creating higher contrast
      // Distribution pattern:
      //       X   1/8 1/8
      // 1/8 1/8 1/8
      //     1/8

      if (x + 1 < width) err_curr[x + 1] += error_eighth;
      if (x + 2 < width) err_curr[x + 2] += error_eighth;
      if (x > 0) err_next1[x - 1] += error_eighth;
      err_next1[x] += error_eighth;
      if (x + 1 < width) err_next1[x + 1] += error_eighth;
      err_next2[x] += error_eighth;
    }

    // Rotate row buffers: next1 becomes current, next2 becomes next1, clear next2
    for (int i = 0; i < width; i++) {
      err_curr[i] = err_next1[i];
      err_next1[i] = err_next2[i];
      err_next2[i] = 0;
    }
  }
}
