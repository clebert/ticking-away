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

// -------------------------------------------------------------------------------------------------
// Direct Quantization Function
// -------------------------------------------------------------------------------------------------

// Convert sRGB float framebuffer to sRGB uint8 framebuffer.
// Clamps values to [0, 1] and rounds to nearest uint8.
// Input:  float_fb - sRGB framebuffer (RGBA, 0.0-1.0)
// Output: out_fb - sRGB framebuffer (RGBA, 0-255)
void quantize_direct_apply(const float *float_fb, uint8_t *out_fb, int width, int height);
