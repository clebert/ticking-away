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

// Convert float framebuffer (linear space) to uint8_t framebuffer (gamma-corrected sRGB).
// Applies proper sRGB transfer function with optional film grain in perceptual (sRGB) space.
// Grain is applied AFTER gamma correction for authentic film grain look (perceptually uniform).
// Vignette dithering is also applied in sRGB space to eliminate banding in dark gradients.
// preserve_alpha: 1 = read alpha from float_fb (for transparent PNG), 0 = always opaque
// dither_enabled: 1 = apply dithering to 6-color palette, 0 = normal quantization
// palette_mode: 0=IDEAL, 1=DEVICE, 2=BLEND (used when dither_enabled)
// palette_saturation: 0.0-1.0, blend factor (only used when palette_mode=BLEND)
// dither_kernel: 0=ATKINSON (75%), 1=FLOYD_STEINBERG (100%)
// dither_oklab_error: 0=linear RGB error diffusion, 1=OkLab error diffusion
// force_black_background: 1 = force background pixels to palette black (no dither noise)
static void finalize_framebuffer(
  const float* float_fb, uint8_t* out_fb,
  int width, int height,
  float grain_intensity,    // 0.0-1.0
  float grain_scale,        // DPR to scale grain (1.0 = no scaling)
  float cx, float cy, float radius,  // Watch circle for grain region
  int apply_vignette_dither,  // 1 = dither vignette region (outside circle)
  const Prism* prism,       // Prism for grain_prism_only mode (can be NULL)
  int grain_prism_only,     // 1 = only apply grain inside prism
  float grain_brightness_threshold,  // 0.01-1.0: brightness at which grain reaches full intensity
  int preserve_alpha,       // 1 = preserve alpha from float_fb, 0 = always opaque
  int dither_enabled,       // 1 = apply dithering to 6-color palette
  int palette_mode,         // 0=IDEAL, 1=DEVICE, 2=BLEND
  float palette_saturation, // 0.0-1.0: blend factor (only used when palette_mode=BLEND)
  float dither_strength,    // 0.0-1.0: error diffusion strength
  int dither_kernel,        // 0=ATKINSON (75%), 1=FLOYD_STEINBERG (100%)
  int dither_oklab_error,   // 0=linear RGB error diffusion, 1=OkLab error diffusion
  int force_black_background // 1 = force background pixels to palette black (no dither noise)
) {
  // Apply error diffusion dithering directly from linear RGB
  // Skip all preprocessing (grain, vignette dither) - not applicable for e-ink output
  if (dither_enabled) {
    dither_buffer(float_fb, out_fb, width, height, (DitherPaletteMode)palette_mode, palette_saturation, preserve_alpha, dither_strength, (DitherKernel)dither_kernel, dither_oklab_error, force_black_background);
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

      // Clamp values (additive blending can exceed 1.0)
      float r = clampf(float_fb[i], 0.0f, 1.0f);
      float g = clampf(float_fb[i + 1], 0.0f, 1.0f);
      float b = clampf(float_fb[i + 2], 0.0f, 1.0f);
      float a = clampf(float_fb[i + 3], 0.0f, 1.0f);

      // Apply proper sRGB gamma correction (linear -> sRGB)
      float out_r = linear_to_srgb(r);
      float out_g = linear_to_srgb(g);
      float out_b = linear_to_srgb(b);

      float px = (float)x + 0.5f;
      float py = (float)y + 0.5f;
      float dx = px - cx;
      float dy = py - cy;
      float dist_sq = dx * dx + dy * dy;

      // Apply film grain in sRGB space (perceptually uniform)
      // Grain is scaled by pixel brightness to avoid noise on black areas
      int in_grain_region = dist_sq <= r2;
      if (grain_prism_only && prism) {
        in_grain_region = in_grain_region && point_in_triangle(px, py,
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

      // Apply vignette dithering in sRGB space (outside watch circle)
      // Dither amplitude ±0.5/255 to break up quantization banding
      // Skip when preserving alpha (transparent background mode)
      if (apply_vignette_dither && !preserve_alpha && dist_sq > r2) {
        uint32_t hash = hash_pixel(x, y);
        float dither = ((float)(hash & 0xFF) / 255.0f - 0.5f) * (2.0f / 255.0f);
        out_r += dither;
        out_g += dither;
        out_b += dither;
      }

      // Quantize to 8-bit
      float final_r = out_r * 255.0f + 0.5f;
      float final_g = out_g * 255.0f + 0.5f;
      float final_b = out_b * 255.0f + 0.5f;
      float final_a = preserve_alpha ? (a * 255.0f + 0.5f) : 255.0f;

      // Clamp and store
      out_fb[i] = final_r < 0.0f ? 0 : (final_r > 255.0f ? 255 : (uint8_t)final_r);
      out_fb[i + 1] = final_g < 0.0f ? 0 : (final_g > 255.0f ? 255 : (uint8_t)final_g);
      out_fb[i + 2] = final_b < 0.0f ? 0 : (final_b > 255.0f ? 255 : (uint8_t)final_b);
      out_fb[i + 3] = final_a < 0.0f ? 0 : (final_a > 255.0f ? 255 : (uint8_t)final_a);
    }
  }
}
