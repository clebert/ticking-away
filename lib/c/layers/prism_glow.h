#pragma once

// =================================================================================================
// Prism Glow Layer
// =================================================================================================
// Renders the inner glow effect on the prism edges. The glow extends inward from the prism
// edges, creating a soft illumination effect that highlights the prism's triangular shape.
//
// The glow uses smooth minimum distance calculation to avoid visible creases at corners,
// and supports multiple falloff curves for different visual styles.

#include "draw/pixel.h"
#include "geometry/types.h"
#include "layers/layer.h"

// -------------------------------------------------------------------------------------------------
// Smooth Minimum
// -------------------------------------------------------------------------------------------------
// Polynomial smooth minimum function for blending distances near corners.
// Avoids gradient discontinuity (dark creases) at prism vertices.

float smooth_min(float a, float b, float k);

// -------------------------------------------------------------------------------------------------
// Distance Functions
// -------------------------------------------------------------------------------------------------

// Compute smooth minimum distance from point to any prism edge.
// Uses smooth_min to blend distances near corners.
// smooth_k: smoothing factor (typically glow_width * 0.5)
float prism_min_edge_distance(float px, float py, const Prism *prism, float smooth_k);

// -------------------------------------------------------------------------------------------------
// Glow Drawing
// -------------------------------------------------------------------------------------------------

// Draw prism with inner glow effect.
// r, g, b: Linear RGB color values (0.0-1.0)
// glow_width: How far the glow extends inward (in pixels)
// intensity: Brightness multiplier (0.0-1.0)
// falloff: Falloff curve type
void prism_glow_draw(float *fb, int width, int height, const Prism *prism, float r, float g,
                     float b, float glow_width, float intensity, FalloffType falloff);

// -------------------------------------------------------------------------------------------------
// Layer Interface
// -------------------------------------------------------------------------------------------------

// Render the prism glow layer using RenderContext.
// Reads glow configuration from ctx->glow_config.
void layer_prism_glow_render(const RenderContext *ctx);

// Layer descriptor
extern const Layer LAYER_PRISM_GLOW;
