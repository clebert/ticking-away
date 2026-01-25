#pragma once

// =================================================================================================
// Direct Quantizer
// =================================================================================================
// Simple quantization from sRGB float (0.0-1.0) to sRGB uint8 (0-255).
//
// This is the non-dithered output path used when dithering is disabled.
// Assumes input framebuffer is already in sRGB space (gamma correction applied).
//
// Input:  sRGB framebuffer (float 0.0-1.0, RGBA)
// Output: sRGB framebuffer (uint8_t 0-255, RGBA)

#include <stdint.h>

#include "fastmath.h"

// -------------------------------------------------------------------------------------------------
// Direct Quantization Functions
// -------------------------------------------------------------------------------------------------

// Round non-negative float to uint8_t (assumes f >= 0)
// NOLINTNEXTLINE(bugprone-incorrect-roundings)
static inline uint8_t round_f_to_u8(float f) { return (uint8_t)(f + 0.5f); }

// Convert a single RGBA pixel from float to uint8.
// Clamps each channel to [0, 1] and rounds to nearest uint8.
static inline void quantize_direct_pixel(const float *in, uint8_t *out) {
  out[0] = round_f_to_u8(clampf(in[0], 0.0f, 1.0f) * 255.0f);
  out[1] = round_f_to_u8(clampf(in[1], 0.0f, 1.0f) * 255.0f);
  out[2] = round_f_to_u8(clampf(in[2], 0.0f, 1.0f) * 255.0f);
  out[3] = round_f_to_u8(clampf(in[3], 0.0f, 1.0f) * 255.0f);
}

// Convert sRGB float framebuffer to sRGB uint8 framebuffer.
// Clamps values to [0, 1] and rounds to nearest uint8.
// Input:  float_fb - sRGB framebuffer (RGBA, 0.0-1.0)
// Output: out_fb - sRGB framebuffer (RGBA, 0-255)
void quantize_direct_apply(const float *float_fb, uint8_t *out_fb, int width, int height);
