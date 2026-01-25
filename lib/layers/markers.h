#pragma once

// =================================================================================================
// Markers Layer
// =================================================================================================
// Renders the hour markers around the watch face. 12 markers are drawn at each hour position,
// extending inward from near the watch edge toward the center. Each marker is rendered as a
// glowing line with configurable length, width, intensity, and falloff.

#include "config.h"
#include "layers/layer.h"

// -------------------------------------------------------------------------------------------------
// Marker Drawing
// -------------------------------------------------------------------------------------------------

// Draw all 12 hour markers around the watch face.
// cx, cy: watch center
// radius: watch radius
// config: marker configuration (length, glow width, intensity, falloff)
void markers_draw(float *fb, int width, int height, float cx, float cy, float radius,
                  const MarkerConfig *config);

// -------------------------------------------------------------------------------------------------
// Layer Interface
// -------------------------------------------------------------------------------------------------

// Render the markers layer using RenderContext.
// Reads marker configuration from ctx->marker_config.
// If marker_config is nullptr or marker_config->visible is 0, does nothing.
void layer_markers_render(const RenderContext *ctx);

// Layer descriptor
extern const Layer LAYER_MARKERS;
