#pragma once

// =================================================================================================
// Background Layer
// =================================================================================================
// Initializes the framebuffer with pure black inside the watch circle and transparent black
// outside. This is the first layer rendered, providing a clean canvas for subsequent layers.
//
// Inside circle: RGB=(0,0,0), Alpha=1.0 (opaque black)
// Outside circle: RGB=(0,0,0), Alpha=0.0 (transparent, UI fills this later via vignette effect)

#include "layers/layer.h"

// -------------------------------------------------------------------------------------------------
// Layer Declaration
// -------------------------------------------------------------------------------------------------

// Render the background layer. Fills the entire framebuffer:
// - Inside watch circle: opaque black (alpha=1)
// - Outside watch circle: transparent black (alpha=0)
//
// Required context fields: fb, width, height, cx, cy, radius
void layer_background_render(const RenderContext *ctx);

// Layer descriptor for use with scene composition
extern const Layer LAYER_BACKGROUND;
