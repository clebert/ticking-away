#pragma once

#include "quantize/dither.h"
#include <stdint.h>

enum { PACK_WIDTH = 1600, PACK_HEIGHT = 1200, PACK_BUFFER_SIZE = 480000 };

void pack_for_display(const uint8_t *rgba, const DitherRGB *palette, int palette_count,
                      uint8_t *packed_left, uint8_t *packed_right, int width, int height);
