#pragma once

#include "color.h"
#include "dither.h"
#include "geometry.h"
#include "prism.h"

// =================================================================================================
// Framebuffer Conversion (Linear → Gamma)
// =================================================================================================

// Simple hash function for deterministic noise (dithering, film grain)
static inline uint32_t hash_pixel(int x, int y) {
  uint32_t h = (uint32_t)(x * 374761393 + y * 668265263);
  h = (h ^ (h >> 13)) * 1274126177;
  return h ^ (h >> 16);
}

// Apply UI background (grey with vignette) to pixels outside the watch circle.
// This is called AFTER dithering/processing so UI elements don't get dithered.
// Operates on the final sRGB uint8_t output buffer.
// transparent_background: 1 = leave outside transparent (for PNG export), 0 = apply grey + vignette
// vignette_enabled: 1 = apply vignette darkening to background, 0 = flat grey
static void apply_ui_background(
  uint8_t* out_fb, int width, int height,
  float cx, float cy, float radius,
  int transparent_background,
  int vignette_enabled
) {
  // Skip if transparent background is requested (PNG export mode)
  if (transparent_background) {
    return;
  }

  // Background color in sRGB (value 35)
  uint8_t bg_base = 35;

  // Vignette parameters
  float max_dist = sqrtf_impl((float)(width * width + height * height)) * 0.5f;
  float vignette_strength = vignette_enabled ? 0.4f : 0.0f;  // Max 40% darkening at corners

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;

      if (dist2 > r2) {
        int idx = row_offset + x * 4;
        uint8_t clamped = bg_base;

        if (vignette_enabled) {
          // Calculate vignette factor
          float dist_from_center = sqrtf_impl(dist2);
          float vignette_t = clampf((dist_from_center - radius) / (max_dist - radius), 0.0f, 1.0f);
          // Smoothstep for perceptually smoother gradient
          float smooth_t = vignette_t * vignette_t * (3.0f - 2.0f * vignette_t);
          float vignette = 1.0f - smooth_t * vignette_strength;

          // Apply vignette dithering to break up banding in dark gradients
          uint32_t hash = hash_pixel(x, y);
          float dither = ((float)(hash & 0xFF) / 255.0f - 0.5f) * 2.0f;

          float final_val = (float)bg_base * vignette + dither;
          clamped = final_val < 0.0f ? 0 : (final_val > 255.0f ? 255 : (uint8_t)(final_val + 0.5f));
        }

        out_fb[idx] = clamped;
        out_fb[idx + 1] = clamped;
        out_fb[idx + 2] = clamped;
        out_fb[idx + 3] = 255;
      }
    }
  }
}

// Convert float framebuffer (linear space) to uint8_t framebuffer (gamma-corrected sRGB).
// Applies proper sRGB transfer function with optional film grain in perceptual (sRGB) space.
// Grain is applied AFTER gamma correction for authentic film grain look (perceptually uniform).
// After processing, applies UI background (grey + vignette) outside the watch circle.
//
// transparent_background: 1 = preserve alpha from float_fb (for PNG export), 0 = opaque with UI bg
// vignette_enabled: 1 = apply vignette to UI background, 0 = flat grey background
// dither_enabled: 1 = apply dithering to 6-color palette (skips grain), 0 = normal quantization
// palette_mode: 0=IDEAL, 1=DEVICE, 2=BLEND (used when dither_enabled)
// palette_saturation: 0.0-1.0, blend factor (only used when palette_mode=BLEND)
// dither_kernel: 0=ATKINSON (75%), 1=FLOYD_STEINBERG (100%)
// dither_oklab_error: 0=linear RGB error diffusion, 1=OkLab error diffusion
// dither_bw_threshold: OkLab chroma threshold for B/W-only dithering (0.0 = disabled)
static void finalize_framebuffer(
  const float* float_fb, uint8_t* out_fb,
  int width, int height,
  float grain_intensity,    // 0.0-1.0
  float grain_scale,        // DPR to scale grain (1.0 = no scaling)
  float cx, float cy, float radius,  // Watch circle for grain region and UI background
  const Prism* prism,       // Prism for grain_prism_only mode (can be NULL)
  int grain_prism_only,     // 1 = only apply grain inside prism
  float grain_brightness_threshold,  // 0.01-1.0: brightness at which grain reaches full intensity
  int transparent_background, // 1 = transparent outside circle (for PNG export)
  int vignette_enabled,     // 1 = apply vignette to UI background
  int dither_enabled,       // 1 = apply dithering to 6-color palette
  int palette_mode,         // 0=IDEAL, 1=DEVICE, 2=BLEND
  float palette_saturation, // 0.0-1.0: blend factor (only used when palette_mode=BLEND)
  float dither_strength,    // 0.0-1.0: error diffusion strength
  int dither_kernel,        // 0=ATKINSON (75%), 1=FLOYD_STEINBERG (100%)
  int dither_oklab_error,   // 0=linear RGB error diffusion, 1=OkLab error diffusion
  float dither_bw_threshold // OkLab chroma threshold (0.0-1.0): pixels below this use B/W only
) {
  // Apply error diffusion dithering directly from linear RGB
  // Skip grain - not applicable for e-ink output
  if (dither_enabled) {
    dither_buffer(float_fb, out_fb, width, height, (DitherPaletteMode)palette_mode,
                  palette_saturation, transparent_background, dither_strength,
                  (DitherKernel)dither_kernel, dither_oklab_error, dither_bw_threshold);
    // Apply UI background after dithering (grey + vignette outside circle)
    apply_ui_background(out_fb, width, height, cx, cy, radius,
                        transparent_background, vignette_enabled);
    return;
  }

  // Grain strength in sRGB space: ±6% at full intensity (≈ ±15/255, classic film grain)
  // Applied in perceptual space for uniform noise across all brightness levels.
  float grain_strength = grain_intensity * 0.06f;

  // Brightness threshold (0-1) at which grain reaches full intensity.
  // Below this, grain fades linearly to zero (avoids noise on black areas).
  // Lower = more grain on dark pixels, higher = grain only on bright pixels.
  float grain_brightness_scale = 1.0f / grain_brightness_threshold;
  int apply_grain = grain_intensity > 0.0f;

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int i = (y * width + x) * 4;

      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;
      float dx = px - cx;
      float dy = py - cy;
      float dist_sq = dx * dx + dy * dy;

      // Skip pixels outside circle - UI background will fill these
      if (dist_sq > r2) {
        // Set to black with zero alpha (UI background fills later)
        out_fb[i] = 0;
        out_fb[i + 1] = 0;
        out_fb[i + 2] = 0;
        out_fb[i + 3] = 0;
        continue;
      }

      // Clamp values (additive blending can exceed 1.0)
      float r = clampf(float_fb[i], 0.0f, 1.0f);
      float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
      float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      // Apply proper sRGB gamma correction (linear -> sRGB)
      float out_r = linear_to_srgb(r);
      float out_g = linear_to_srgb(g);
      float out_b = linear_to_srgb(b);

      // Apply film grain in sRGB space (perceptually uniform)
      // Grain is scaled by pixel brightness to avoid noise on black areas
      int in_grain_region = 1;  // Already inside circle from check above
      if (grain_prism_only && prism) {
        in_grain_region = point_in_triangle(px, py,
          prism->vertices[0], prism->vertices[1],
          prism->vertices[2], prism->vertices[3],
          prism->vertices[4], prism->vertices[5]);
      }
      if (apply_grain && in_grain_region) {
        float brightness = (out_r + out_g + out_b) / 3.0f;
        float brightness_scale = clampf(brightness * grain_brightness_scale, 0.0f, 1.0f);

        int gx = (int)((float)x / grain_scale);
        int gy = (int)((float)y / grain_scale);
        uint32_t hash = hash_pixel(gx, gy);
        float grain = ((float)(hash & 0xFF) / 255.0f - 0.5f) * grain_strength * 2.0f * brightness_scale;

        out_r += grain;
        out_g += grain;
        out_b += grain;
      }

      // Quantize to 8-bit
      float final_r = out_r * 255.0f + 0.5f;
      float final_g = out_g * 255.0f + 0.5f;
      float final_b = out_b * 255.0f + 0.5f;
      float final_a = transparent_background ? (a * 255.0f + 0.5f) : 255.0f;

      // Clamp and store
      out_fb[i] = final_r < 0.0f ? 0 : (final_r > 255.0f ? 255 : (uint8_t)final_r);
      out_fb[i + 1] = final_g < 0.0f ? 0 : (final_g > 255.0f ? 255 : (uint8_t)final_g);
      out_fb[i + 2] = final_b < 0.0f ? 0 : (final_b > 255.0f ? 255 : (uint8_t)final_b);
      out_fb[i + 3] = final_a < 0.0f ? 0 : (final_a > 255.0f ? 255 : (uint8_t)final_a);
    }
  }

  // Apply UI background after processing (grey + vignette outside circle)
  apply_ui_background(out_fb, width, height, cx, cy, radius,
                      transparent_background, vignette_enabled);
}
