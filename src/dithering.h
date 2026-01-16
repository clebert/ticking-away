#pragma once

#include <stdint.h>

#define DITHER_MAX_WIDTH 5120

// Dithering modes (ordered by bit depth, then algorithm)
#define DITHER_MODE_NONE 0
#define DITHER_MODE_1BIT_ATKINSON 1
#define DITHER_MODE_2BIT_ATKINSON 2
#define DITHER_MODE_2BIT_BAYER 3
#define DITHER_MODE_4BIT_BAYER 4

// Convert RGB to luminance using standard weights
static inline int luminance(int r, int g, int b) {
  return (r * 299 + g * 587 + b * 114) / 1000;
}

static inline int clamp(int v, int lo, int hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

// Quantize luminance to discrete levels based on dithering mode
// 1-bit: 2 levels (0, 255)
// 2-bit: 4 levels (0, 85, 170, 255) - https://docs.usetrmnl.com/go/diy/imagemagick-guide#h_6b95d41fbd-1
// 4-bit: 16 levels (0, 17, 34, ..., 255)
static inline int quantize_luminance(int lum, int mode) {
  int clamped = clamp(lum, 0, 255);

  if (mode == DITHER_MODE_1BIT_ATKINSON) {
    return (clamped < 128) ? 0 : 255;
  } else if (mode == DITHER_MODE_2BIT_ATKINSON || mode == DITHER_MODE_2BIT_BAYER) {
    return ((clamped + 42) / 85) * 85;
  } else {
    return ((clamped + 8) / 17) * 17;
  }
}

// 4x4 Bayer matrix for ordered dithering (values 0-15, representing thresholds)
static const int bayer4x4[4][4] = {
  {  0,  8,  2, 10 },
  { 12,  4, 14,  6 },
  {  3, 11,  1,  9 },
  { 15,  7, 13,  5 }
};

// Atkinson error diffusion for 1-bit/2-bit, Bayer ordered dithering for 4-bit/2-bit-bayer
static inline void apply_dithering(uint8_t* fb, int width, int height, int mode) {
  if (width > DITHER_MAX_WIDTH || mode == DITHER_MODE_NONE) return;

  // 2-bit Bayer: ordered dithering with 4 levels (0, 85, 170, 255)
  if (mode == DITHER_MODE_2BIT_BAYER) {
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int idx = (y * width + x) * 4;
        int lum = luminance(fb[idx], fb[idx + 1], fb[idx + 2]);

        // Add threshold offset: (bayer/16 - 0.5) * step, where step = 85 for 4 levels
        int threshold = bayer4x4[y & 3][x & 3];
        int offset = (threshold * 85 / 16) - 43;  // Range: -43 to +36
        int level = quantize_luminance(lum + offset, mode);

        fb[idx] = level;
        fb[idx + 1] = level;
        fb[idx + 2] = level;
      }
    }
    return;
  }

  // 4-bit Bayer: ordered dithering with 16 levels (no error accumulation, consistent pattern)
  if (mode == DITHER_MODE_4BIT_BAYER) {
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int idx = (y * width + x) * 4;
        int lum = luminance(fb[idx], fb[idx + 1], fb[idx + 2]);

        // Add threshold offset: (bayer/16 - 0.5) * step, where step = 17 for 16 levels
        int threshold = bayer4x4[y & 3][x & 3];
        int offset = (threshold * 17 / 16) - 8;  // Range: -8 to +7
        int level = quantize_luminance(lum + offset, mode);

        fb[idx] = level;
        fb[idx + 1] = level;
        fb[idx + 2] = level;
      }
    }
    return;
  }

  // 1-bit/2-bit: Atkinson error diffusion (75% for high contrast)
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
