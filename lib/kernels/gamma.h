#pragma once

// =================================================================================================
// Gamma Kernel
// =================================================================================================
// Converts framebuffer between linear RGB and sRGB color spaces.
//
// sRGB is the standard color space for display. The transfer function has:
// - A linear region below 0.0031308 (multiply by 12.92)
// - A power curve above (x^(1/2.4) with offset)
//
// This kernel operates in-place on float framebuffers.

#include "kernel.h"
#include <stdint.h>

// -------------------------------------------------------------------------------------------------
// Gamma Configuration
// -------------------------------------------------------------------------------------------------
// Currently the sRGB transfer function is fixed (IEC 61966-2-1 standard).
// Config struct reserved for future extensions (e.g., custom gamma curves).

typedef struct {
  int reserved; // Placeholder for future options
} GammaConfig;

// -------------------------------------------------------------------------------------------------
// Color Space Conversion Functions
// -------------------------------------------------------------------------------------------------

// Convert sRGB (0-255) to linear (0.0-1.0) using proper sRGB transfer function.
// Uses piecewise function: linear region below 0.04045, power curve above.
float gamma_srgb_to_linear(uint8_t srgb);

// Convert linear (0.0-1.0) to sRGB (0.0-1.0) using proper sRGB transfer function.
// Uses piecewise function: linear region below 0.0031308, power curve above.
float gamma_linear_to_srgb(float linear);

// -------------------------------------------------------------------------------------------------
// Kernel Function
// -------------------------------------------------------------------------------------------------

// Apply gamma correction (linear -> sRGB) to entire framebuffer.
// Converts float fb from linear RGB to sRGB space in-place.
// Config can be NULL (uses standard sRGB transfer function).
// Cache is unused (pass NULL).
void kernel_gamma_apply(float *fb, int width, int height, const void *config, const void *cache);

// Kernel descriptor for pipeline registration
extern const Kernel KERNEL_GAMMA;
