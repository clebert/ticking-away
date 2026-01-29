#pragma once

// =================================================================================================
// Line Drawing Module
// =================================================================================================
// Distance-field based line drawing with glow effects and clipping.
// Lines are rendered with configurable falloff and intensity gradients.

#include "pixel.h"

// -------------------------------------------------------------------------------------------------
// Clipping Regions
// -------------------------------------------------------------------------------------------------

// Triangle clipping region (6 floats: x0, y0, x1, y1, x2, y2)
// Pass nullptr to disable triangle clipping
typedef const float *ClipTriangle;

// Circle clipping region (3 floats: cx, cy, radius)
// Pass nullptr to disable circle clipping
typedef const float *ClipCircle;

// Triangle exclusion region (6 floats: x0, y0, x1, y1, x2, y2)
// Pixels inside this triangle are skipped. Pass nullptr to disable.
typedef const float *ExcludeTriangle;

// -------------------------------------------------------------------------------------------------
// Line Drawing with Glow
// -------------------------------------------------------------------------------------------------

// Draw a line with glow effect using uniform intensity along its length.
// Uses additive blending (for light rays, glows).
//
// Parameters:
//   fb: float RGBA framebuffer (width * height * 4)
//   x0, y0, x1, y1: line endpoints
//   r, g, b: color in [0.0, 1.0] linear space
//   glow_width: radius of glow effect in pixels
//   intensity: overall brightness multiplier
//   falloff: type of falloff curve (FALLOFF_LINEAR, etc.)
//   clip_triangle: only draw inside this triangle (nullptr = no clip)
//   clip_circle: only draw inside this circle (nullptr = no clip)
//   exclude_triangle: skip pixels inside this triangle (nullptr = no exclude)
void line_draw_glow(float *fb, int width, int height, float x0, float y0, float x1, float y1,
                    float r, float g, float b, float glow_width, float intensity,
                    FalloffType falloff, ClipTriangle clip_triangle, ClipCircle clip_circle,
                    ExcludeTriangle exclude_triangle);

// Draw a line with glow effect and intensity gradient along its length.
// Intensity is linearly interpolated from intensity_start at (x0, y0)
// to intensity_end at (x1, y1).
//
// Parameters:
//   intensity_start: intensity at start point (x0, y0)
//   intensity_end: intensity at end point (x1, y1)
//   (other parameters same as line_draw_glow)
void line_draw_glow_gradient(float *fb, int width, int height, float x0, float y0, float x1,
                             float y1, float r, float g, float b, float glow_width,
                             float intensity_start, float intensity_end, FalloffType falloff,
                             ClipTriangle clip_triangle, ClipCircle clip_circle,
                             ExcludeTriangle exclude_triangle);
