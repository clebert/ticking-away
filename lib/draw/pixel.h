#pragma once

// =================================================================================================
// Pixel Operations Module
// =================================================================================================
// Low-level pixel blending operations for float framebuffers in linear color space.
// All operations assume pre-multiplied alpha and RGBA layout (4 floats per pixel).

#include "kernels/kernel.h" // FalloffType

// -------------------------------------------------------------------------------------------------
// Falloff Computation
// -------------------------------------------------------------------------------------------------

// Compute falloff value for glow effects.
// t: normalized distance (0 at center, 1 at edge)
// Returns intensity multiplier in [0, 1]
float compute_falloff(FalloffType type, float t);

// -------------------------------------------------------------------------------------------------
// Additive Blending
// -------------------------------------------------------------------------------------------------

// Add color to existing pixel (for light/glow effects).
// r, g, b are in [0.0, 1.0] range, a is intensity multiplier.
// Result is clamped during final gamma conversion, not here.
void pixel_add(float *fb, int width, int height, int x, int y, float r, float g, float b, float a);

// -------------------------------------------------------------------------------------------------
// Alpha Blending
// -------------------------------------------------------------------------------------------------

// Blend color over existing pixel using standard alpha compositing.
// r, g, b are in [0.0, 1.0] range, a is alpha (opacity).
// Uses formula: out = src * a + dst * (1 - a)
void pixel_blend(float *fb, int width, int height, int x, int y, float r, float g, float b,
                 float a);
