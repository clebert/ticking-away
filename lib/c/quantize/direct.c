#include "quantize/direct.h"

// =================================================================================================
// Direct Quantization Implementation
// =================================================================================================

void quantize_direct_apply(const float *float_fb, uint8_t *out_fb, int width, int height) {
  int total_pixels = width * height;
  for (int i = 0; i < total_pixels; i++) {
    int idx = i * 4;
    quantize_direct_pixel(&float_fb[idx], &out_fb[idx]);
  }
}
