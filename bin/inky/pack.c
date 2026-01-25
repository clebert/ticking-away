#include "pack.h"

static int find_palette_index(uint8_t r, uint8_t g, uint8_t b, const DitherRGB *palette,
                              int palette_count) {
  int best_idx = 0;
  int best_dist = 0x7FFFFFFF;

  for (int i = 0; i < palette_count; i++) {
    int dr = (int)r - (int)palette[i].r;
    int dg = (int)g - (int)palette[i].g;
    int db = (int)b - (int)palette[i].b;
    int dist = dr * dr + dg * dg + db * db;

    if (dist < best_dist) {
      best_dist = dist;
      best_idx = i;
    }

    if (dist == 0) {
      break;
    }
  }

  return best_idx;
}

static uint8_t palette_to_display_value(int palette_idx) {
  // Display uses 3-bit color values 0-6, but value 4 is unused/reserved.
  // Maps sequential palette indices to display values: 0,1,2,3,5,6 (skipping 4).
  static const uint8_t MAPPING[] = {0, 1, 2, 3, 5, 6};
  if (palette_idx < 0 || palette_idx > 5) {
    return 0;
  }
  return MAPPING[palette_idx];
}

void pack_for_display(const uint8_t *rgba, const DitherRGB *palette, int palette_count,
                      uint8_t *packed_left, uint8_t *packed_right, int width, int height) {
  int idx_left = 0;
  int idx_right = 0;

  // The display uses two controllers (CS0 and CS1), each handling half the columns.
  // After the -90 degree rotation, the rotated image is split at the midpoint.
  int half_height = height / 2;

  for (int new_row = 0; new_row < width; new_row++) {
    for (int new_col = 0; new_col < height; new_col++) {
      int old_row = (height - 1) - new_col;
      int old_col = new_row;
      int src_idx = (old_row * width + old_col) * 4;

      uint8_t r = rgba[src_idx + 0];
      uint8_t g = rgba[src_idx + 1];
      uint8_t b = rgba[src_idx + 2];

      int palette_idx = find_palette_index(r, g, b, palette, palette_count);
      uint8_t display_val = palette_to_display_value(palette_idx);

      if (new_col < half_height) {
        if ((idx_left & 1) == 0) {
          packed_left[idx_left >> 1] = (display_val << 4);
        } else {
          packed_left[idx_left >> 1] |= (display_val & 0x0F);
        }
        idx_left++;
      } else {
        if ((idx_right & 1) == 0) {
          packed_right[idx_right >> 1] = (display_val << 4);
        } else {
          packed_right[idx_right >> 1] |= (display_val & 0x0F);
        }
        idx_right++;
      }
    }
  }
}
