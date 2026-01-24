#pragma once

#include "drawing.h"
#include "framebuffer.h"
#include "rainbow.h"
#include "ray_paths.h"

// =================================================================================================
// Watch-Specific Drawing
// =================================================================================================

// Initialize watch framebuffer with pure black background inside circle (linear color space)
// Outside circle is set to black with alpha=0 (will be filled with UI background after processing)
static void init_watch_framebuffer_f(
  float* fb, int width, int height,
  float cx, float cy, float radius
) {
  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;
      int idx = row_offset + x * 4;

      if (dist2 <= r2) {
        // Inside watchface - pure black with full alpha
        fb[idx] = 0.0f;
        fb[idx + 1] = 0.0f;
        fb[idx + 2] = 0.0f;
        fb[idx + 3] = 1.0f;
      } else {
        // Outside watchface - black with zero alpha (UI fills this later)
        fb[idx] = 0.0f;
        fb[idx + 1] = 0.0f;
        fb[idx + 2] = 0.0f;
        fb[idx + 3] = 0.0f;
      }
    }
  }
}

// =================================================================================================
// Prism Inner Glow (Distance Field)
// =================================================================================================

// Polynomial smooth minimum for blending distances near corners.
// Creates continuous gradients by smoothly interpolating between two values
// when they are within 'k' of each other. This eliminates the gradient
// discontinuity (visible crease) that occurs with hard min at corners.
static inline float smooth_min(float a, float b, float k) {
  float h = maxf_impl(k - fabsf_impl(a - b), 0.0f) / k;
  return minf_impl(a, b) - h * h * k * 0.25f;
}

// Compute smooth minimum distance from point to any prism edge.
// Uses smooth_min to blend distances near corners, avoiding the gradient
// discontinuity that causes visible dark creases at vertices.
static float min_distance_to_prism_edge(float px, float py, const Prism* prism, float smooth_k) {
  float d0 = point_to_segment_distance(px, py,
    prism->vertices[0], prism->vertices[1],
    prism->vertices[2], prism->vertices[3]);
  float d1 = point_to_segment_distance(px, py,
    prism->vertices[2], prism->vertices[3],
    prism->vertices[4], prism->vertices[5]);
  float d2 = point_to_segment_distance(px, py,
    prism->vertices[4], prism->vertices[5],
    prism->vertices[0], prism->vertices[1]);

  // Chain smooth_min for all three edges
  return smooth_min(smooth_min(d0, d1, smooth_k), d2, smooth_k);
}

// Draw prism with inner glow effect (linear color space)
// glow_width: how far the glow extends inward (in pixels)
// intensity: 0.0-1.0 multiplier for glow brightness
// falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
static void draw_prism_glow_f(
  float* fb, int width, int height,
  const Prism* prism,
  float r, float g, float b,
  float glow_width,
  float intensity,
  int falloff
) {
  float v0x = prism->vertices[0], v0y = prism->vertices[1];
  float v1x = prism->vertices[2], v1y = prism->vertices[3];
  float v2x = prism->vertices[4], v2y = prism->vertices[5];

  float min_x = v0x < v1x ? (v0x < v2x ? v0x : v2x) : (v1x < v2x ? v1x : v2x);
  float max_x = v0x > v1x ? (v0x > v2x ? v0x : v2x) : (v1x > v2x ? v1x : v2x);
  float min_y = v0y < v1y ? (v0y < v2y ? v0y : v2y) : (v1y < v2y ? v1y : v2y);
  float max_y = v0y > v1y ? (v0y > v2y ? v0y : v2y) : (v1y > v2y ? v1y : v2y);

  int x_start = (int)min_x - 1;
  int x_end = (int)max_x + 2;
  int y_start = (int)min_y - 1;
  int y_end = (int)max_y + 2;

  if (x_start < 0) x_start = 0;
  if (y_start < 0) y_start = 0;
  if (x_end > width) x_end = width;
  if (y_end > height) y_end = height;

  for (int y = y_start; y < y_end; y++) {
    for (int x = x_start; x < x_end; x++) {
      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;

      if (!point_in_triangle(px, py, v0x, v0y, v1x, v1y, v2x, v2y)) {
        continue;
      }

      float dist = min_distance_to_prism_edge(px, py, prism, glow_width * 0.5f);

      if (dist < glow_width) {
        float t = dist / glow_width;
        float falloff_value = compute_falloff(falloff, t);

        float alpha = falloff_value * intensity;
        set_pixel_additive_f(fb, width, height, x, y, r, g, b, alpha);
      }
    }
  }
}

// Draw watch overlay (hour markers) - linear color space
// Uses pure white for clean, simple rendering.
// Always draws all 12 hour markers.
static void draw_watch_overlay_f(
  float* fb, int width, int height,
  float cx, float cy, float radius,
  float marker_length_percent,
  float marker_glow_width,
  float marker_glow_intensity,
  int marker_glow_falloff
) {
  float glow_width = radius * marker_glow_width;
  float circle_clip[3] = { cx, cy, radius };

  for (int h = 0; h < 12; h++) {
    float angle = ((float)h - 3.0f) * 30.0f * PI / 180.0f;
    float inner_r = radius * (1.0f - marker_length_percent);
    float outer_r = radius * 0.98f;

    float cos_a = cosf_approx(angle);
    float sin_a = sinf_approx(angle);
    float x0 = cx + cos_a * inner_r;
    float y0 = cy + sin_a * inner_r;
    float x1 = cx + cos_a * outer_r;
    float y1 = cy + sin_a * outer_r;

    // Draw with pure white
    draw_line_with_glow_additive_f(fb, width, height,
      x0, y0, x1, y1,
      1.0f, 1.0f, 1.0f,
      glow_width, marker_glow_intensity, marker_glow_falloff,
      0, circle_clip, 0);
  }
}

// =================================================================================================
// Watchface Rendering
// =================================================================================================

// Render the watchface scene.
// - entry_x, entry_y: minute hand position (light source)
// - hour_angle: angle to hour position from center
// - rainbow_spread: 0.0 (no spread) to 1.0 (30 degree spread)
// - show_markers: if true, show watch overlay (hour markers)
// - prism_r, prism_g, prism_b: RGB values (0-255) for prism stroke
// - glow_width_percent: prism glow width as fraction of radius
// - glow_intensity: 0.0-1.0 multiplier for prism glow brightness
// - glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - ray_glow_width: glow width for rays in pixels
// - ray_glow_intensity: 0.0-1.0 multiplier for ray glow brightness
// - ray_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - marker_length_percent: how far markers extend towards center (0.0-1.0)
// - marker_glow_width: glow width for markers as fraction of radius
// - marker_glow_intensity: 0.0-1.0 multiplier for marker glow brightness
// - marker_glow_falloff: 0=linear, 1=quadratic, 2=cubic, 3=exponential
// - grain_intensity: 0.0-1.0 intensity of film grain effect
// - grain_scale: DPR to scale grain size (1.0 = no scaling)
// - grain_prism_only: 1 = only apply grain inside prism
// - gradient_fill: 1 = fill gradient between rainbow rays
// - vignette: 1 = apply vignette effect to background
// - palette: ColorPalette enum value (0-4) for rainbow color scheme
// - reverse_spectrum: 1 = reverse spectral order (album art style: red on top)
// - transparent_background: 1 = transparent outside circle (for PNG export)
// - palette_mode: 0=IDEAL, 1=DEVICE, 2=BLEND (for dithering)
// - palette_saturation: 0.0-1.0, blend factor (only used when palette_mode=BLEND)
// - dither_kernel: 0=ATKINSON (75%), 1=FLOYD_STEINBERG (100%)
// - dither_bw_threshold: OkLab chroma threshold for B/W-only dithering (0.0 = disabled)
// - dither_chroma_weight: 0.5-4.0, weight for hue/chroma vs lightness (1.0 = default, higher = prioritize hue)
static void render_watchface_scene(
  float* float_fb,  // Float buffer for linear rendering
  uint8_t* fb,      // Output buffer (gamma-corrected)
  int width, int height,
  float cx, float cy, float radius,
  float entry_x, float entry_y,
  float hour_angle,
  float rainbow_spread,
  const Prism* prism,
  int show_markers,
  uint8_t prism_r,
  uint8_t prism_g,
  uint8_t prism_b,
  float glow_width_percent,
  float glow_intensity,
  int glow_falloff,
  float ray_glow_width,
  float ray_glow_intensity,
  int ray_glow_falloff,
  float marker_length_percent,
  float marker_glow_width,
  float marker_glow_intensity,
  int marker_glow_falloff,
  float grain_intensity,
  float grain_scale,
  int grain_prism_only,
  int gradient_fill,
  int vignette,
  int palette,
  int reverse_spectrum,
  float grain_brightness_threshold,
  int transparent_background,
  int dither_enabled,
  int palette_mode,
  float palette_saturation,
  float dither_strength,
  int dither_kernel,
  int dither_oklab_error,
  float dither_bw_threshold,
  float dither_chroma_weight
) {
  // Initialize precomputed data (reinitializes if palette changed)
  init_band_colors((ColorPalette)palette);

  // Convert prism color from sRGB to linear
  float prism_r_f = srgb_to_linear(prism_r);
  float prism_g_f = srgb_to_linear(prism_g);
  float prism_b_f = srgb_to_linear(prism_b);

  // Initialize background with pure black inside circle
  // UI background (grey + vignette) is applied after processing in finalize_framebuffer
  init_watch_framebuffer_f(float_fb, width, height, cx, cy, radius);

  // Compute all ray path geometry (decoupled from rendering)
  RayPaths paths = compute_ray_paths(cx, cy, radius, entry_x, entry_y, hour_angle, rainbow_spread, prism);

  if (!paths.hits_prism) {
    // Ray doesn't hit prism - just draw overlay and return
    draw_prism_glow_f(float_fb, width, height, prism, prism_r_f, prism_g_f, prism_b_f,
                      radius * glow_width_percent, glow_intensity, glow_falloff);
    if (show_markers) {
      draw_watch_overlay_f(float_fb, width, height, cx, cy, radius,
                           marker_length_percent,
                           marker_glow_width, marker_glow_intensity, marker_glow_falloff);
    }
    // Convert float buffer to output buffer with sRGB gamma correction and film grain
    finalize_framebuffer(float_fb, fb, width, height,
                         grain_intensity, grain_scale, cx, cy, radius,
                         prism, grain_prism_only, grain_brightness_threshold,
                         transparent_background, vignette,
                         dither_enabled, palette_mode, palette_saturation, dither_strength, dither_kernel, dither_oklab_error, dither_bw_threshold, dither_chroma_weight);
    return;
  }

  // Clipping data for external rays (entry ray and rainbow rays)
  float circle_clip[3] = { cx, cy, radius };

  // Draw gradient fill between rainbow rays (when enabled and spread > 0)
  if (gradient_fill && paths.gradient_valid) {
    float gradient_intensity = 1.0f;

    // Compute angles from CENTER to where boundary rays hit CIRCLE
    float ext_angle_first = atan2_approx(paths.border_first_y - cy, paths.border_first_x - cx);
    float ext_angle_last = atan2_approx(paths.border_last_y - cy, paths.border_last_x - cx);

    // Extend gradient angles to include infrared/ultraviolet zones
    float ray_span = ext_angle_last - ext_angle_first;
    if (ray_span > PI) ray_span -= 2.0f * PI;
    if (ray_span < -PI) ray_span += 2.0f * PI;
    float edge_margin = ray_span * EDGE_MARGIN_FACTOR;
    float ext_angle_infrared = ext_angle_first - edge_margin;
    float ext_angle_ultraviolet = ext_angle_last + edge_margin;

    // Draw continuous gradient outside prism (uses center as origin)
    draw_gradient_continuous_f(
      float_fb, width, height, GRADIENT_EXTERNAL,
      cx, cy,  // origin = center
      cx, cy, radius,
      ext_angle_infrared, ext_angle_ultraviolet,
      prism, gradient_intensity, reverse_spectrum
    );

    // Draw continuous gradient inside prism
    // Origin point: when bouncing, light spreads from bounce point; otherwise from entry point
    float grad_origin_x = paths.needs_bounce ? paths.bounce_x : paths.entry_x;
    float grad_origin_y = paths.needs_bounce ? paths.bounce_y : paths.entry_y;

    // Use first and last band internal exit points for gradient boundaries
    const BandPath* first_band = &paths.bands[0];
    const BandPath* last_band = &paths.bands[NUM_BANDS - 1];

    // Compute angles from origin to internal exit points (ray positions)
    float internal_angle_first = atan2_approx(first_band->internal_exit_y - grad_origin_y,
                                               first_band->internal_exit_x - grad_origin_x);
    float internal_angle_last = atan2_approx(last_band->internal_exit_y - grad_origin_y,
                                              last_band->internal_exit_x - grad_origin_x);

    // Extend internal gradient angles to include infrared/ultraviolet zones
    float internal_ray_span = internal_angle_last - internal_angle_first;
    if (internal_ray_span > PI) internal_ray_span -= 2.0f * PI;
    if (internal_ray_span < -PI) internal_ray_span += 2.0f * PI;
    float internal_edge_margin = internal_ray_span * EDGE_MARGIN_FACTOR;
    float internal_angle_infrared = internal_angle_first - internal_edge_margin;
    float internal_angle_ultraviolet = internal_angle_last + internal_edge_margin;

    draw_gradient_continuous_f(
      float_fb, width, height, GRADIENT_INTERNAL,
      grad_origin_x, grad_origin_y,
      0, 0, 0,  // cx, cy, radius unused for internal mode
      internal_angle_infrared, internal_angle_ultraviolet,
      prism, gradient_intensity, reverse_spectrum
    );
  }

  // Compute internal ray fade when gradient is enabled
  // The rays should fade out along their length, from full at entry to zero at exit
  int draw_internal_colored_rays = 1;
  int draw_exit_rays = 1;
  int use_gradient_intensity = 0;  // Use gradient function for spatial fade along ray

  if (gradient_fill && paths.gradient_valid) {
    // Don't draw exit rays at all - gradient handles that region
    draw_exit_rays = 0;

    // Use gradient intensity along the ray length
    use_gradient_intensity = 1;

    // At maximum spread, don't draw internal rays at all
    if (rainbow_spread > 0.99f) {
      draw_internal_colored_rays = 0;
    }
  }

  // Draw all rays per-band using precomputed geometry
  for (int i = 0; i < NUM_BANDS; i++) {
    // When reverse_spectrum is true, reverse the color lookup (album art style)
    int color_idx = reverse_spectrum ? (NUM_BANDS - 1 - i) : i;
    RGB_Linear color = BAND_COLORS_LINEAR[color_idx];
    const BandPath* band = &paths.bands[i];

    // Draw incoming ray (outside prism) - pure white
    if (paths.entry_ray.valid) {
      draw_line_with_glow_additive_f(float_fb, width, height,
        paths.entry_ray.x0, paths.entry_ray.y0,
        paths.entry_ray.x1, paths.entry_ray.y1,
        1.0f, 1.0f, 1.0f, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
        0, circle_clip, prism->vertices);
    }

    // Draw internal path segments
    if (band->internal_seg1.valid) {
      if (paths.needs_bounce) {
        // Entry→bounce segment: pure white (input ray continuation, not dispersion)
        draw_line_with_glow_additive_f(float_fb, width, height,
          band->internal_seg1.x0, band->internal_seg1.y0,
          band->internal_seg1.x1, band->internal_seg1.y1,
          1.0f, 1.0f, 1.0f, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
          prism->vertices, 0, 0);

        // Bounced path: bounce → exit (colored, with fade when gradient enabled)
        if (band->internal_seg2.valid && draw_internal_colored_rays) {
          if (use_gradient_intensity) {
            // Fade intensity along the ray: full at bounce, zero at exit
            draw_line_with_glow_gradient_f(float_fb, width, height,
              band->internal_seg2.x0, band->internal_seg2.y0,
              band->internal_seg2.x1, band->internal_seg2.y1,
              color.r, color.g, color.b, ray_glow_width,
              ray_glow_intensity, 0.0f,  // full intensity at start, zero at end
              ray_glow_falloff, prism->vertices, 0, 0);
          } else {
            draw_line_with_glow_additive_f(float_fb, width, height,
              band->internal_seg2.x0, band->internal_seg2.y0,
              band->internal_seg2.x1, band->internal_seg2.y1,
              color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
              prism->vertices, 0, 0);
          }
        }
      } else {
        // Direct path: entry → exit (colored, with fade when gradient enabled)
        if (draw_internal_colored_rays) {
          if (use_gradient_intensity) {
            // Fade intensity along the ray: full at entry, zero at exit
            draw_line_with_glow_gradient_f(float_fb, width, height,
              band->internal_seg1.x0, band->internal_seg1.y0,
              band->internal_seg1.x1, band->internal_seg1.y1,
              color.r, color.g, color.b, ray_glow_width,
              ray_glow_intensity, 0.0f,  // full intensity at start, zero at end
              ray_glow_falloff, prism->vertices, 0, 0);
          } else {
            draw_line_with_glow_additive_f(float_fb, width, height,
              band->internal_seg1.x0, band->internal_seg1.y0,
              band->internal_seg1.x1, band->internal_seg1.y1,
              color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
              prism->vertices, 0, 0);
          }
        }
      }
    }

    // Draw exit ray (from prism exit to circle edge) - skip when gradient is enabled
    if (band->exit_ray.valid && draw_exit_rays) {
      draw_line_with_glow_additive_f(float_fb, width, height,
        band->exit_ray.x0, band->exit_ray.y0,
        band->exit_ray.x1, band->exit_ray.y1,
        color.r, color.g, color.b, ray_glow_width, ray_glow_intensity, ray_glow_falloff,
        0, circle_clip, prism->vertices);
    }
  }

  // Draw prism with inner glow
  draw_prism_glow_f(float_fb, width, height, prism, prism_r_f, prism_g_f, prism_b_f,
                    radius * glow_width_percent, glow_intensity, glow_falloff);

  // Draw watch overlay (hour markers) if show_markers is set
  if (show_markers) {
    draw_watch_overlay_f(float_fb, width, height, cx, cy, radius,
                         marker_length_percent,
                         marker_glow_width, marker_glow_intensity, marker_glow_falloff);
  }

  // Convert float buffer to output buffer with sRGB gamma correction and film grain
  finalize_framebuffer(float_fb, fb, width, height,
                       grain_intensity, grain_scale, cx, cy, radius,
                       prism, grain_prism_only, grain_brightness_threshold,
                       transparent_background, vignette,
                       dither_enabled, palette_mode, palette_saturation, dither_strength, dither_kernel, dither_oklab_error, dither_bw_threshold, dither_chroma_weight);
}
