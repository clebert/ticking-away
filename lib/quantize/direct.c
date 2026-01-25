#include "quantize/direct.h"

// =================================================================================================
// Direct Quantization Implementation
// =================================================================================================

void quantize_direct_apply(const float *float_fb, uint8_t *out_fb, int width, int height) {
  int total_pixels = width * height;
  for (int i = 0; i < total_pixels; i++) {
    int idx = i * 4;

    // Clamp and convert
    float r = float_fb[idx + 0];
    float g = float_fb[idx + 1];
    float b = float_fb[idx + 2];
    float a = float_fb[idx + 3];

    // Clamp to [0, 1]
    if (r < 0.0f)
      r = 0.0f;
    else if (r > 1.0f)
      r = 1.0f;
    if (g < 0.0f)
      g = 0.0f;
    else if (g > 1.0f)
      g = 1.0f;
    if (b < 0.0f)
      b = 0.0f;
    else if (b > 1.0f)
      b = 1.0f;
    if (a < 0.0f)
      a = 0.0f;
    else if (a > 1.0f)
      a = 1.0f;

    // Convert to uint8 with rounding
    out_fb[idx + 0] = (uint8_t)(r * 255.0f + 0.5f);
    out_fb[idx + 1] = (uint8_t)(g * 255.0f + 0.5f);
    out_fb[idx + 2] = (uint8_t)(b * 255.0f + 0.5f);
    out_fb[idx + 3] = (uint8_t)(a * 255.0f + 0.5f);
  }
}
