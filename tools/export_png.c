// PNG export tool for watchface rendering
// Usage: export_png <time> <resolution> <output.png>
// Example: export_png 7:14 4096 output.png

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include "watchface.h"

// =================================================================================================
// Application Constants (from wasm.c)
// =================================================================================================

#define ANGLE_0 (-PI / 2.0f)   // 12 o'clock position
#define HOUR_ARC (TAU / 12.0f) // 30 degrees per hour

// =================================================================================================
// Default Settings (from stores.ts)
// =================================================================================================

// Prism
#define DEFAULT_PRISM_SIZE 90            // percent
#define DEFAULT_RAINBOW_SPREAD 50        // 0-100
#define DEFAULT_PRISM_GRAY 255           // 0-255
#define DEFAULT_PRISM_BLUE_TINT 100      // 0-100
#define DEFAULT_PRISM_GLOW_WIDTH 6       // 0-10
#define DEFAULT_PRISM_GLOW_INTENSITY 100 // 0-100
#define DEFAULT_PRISM_GLOW_FALLOFF 3     // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential

// Rays
#define DEFAULT_RAY_GLOW_WIDTH 1       // 0-10
#define DEFAULT_RAY_GLOW_INTENSITY 100 // 0-100
#define DEFAULT_RAY_GLOW_FALLOFF 1     // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
#define DEFAULT_GRADIENT_FILL 1        // true
#define DEFAULT_PALETTE 2              // 0=OkLCH, 1=Saturated, 2=Spectral, 3=Neon, 4=Muted
#define DEFAULT_REVERSE_SPECTRUM 1     // true (album art style)

// Markers
#define DEFAULT_MARKER_LENGTH 10          // 0-20 percent
#define DEFAULT_MARKER_GLOW_WIDTH 1       // 0-10
#define DEFAULT_MARKER_GLOW_INTENSITY 100 // 0-100
#define DEFAULT_MARKER_GLOW_FALLOFF 1     // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
#define DEFAULT_SHOW_MARKERS 0            // false

// Background
#define DEFAULT_GRAIN_INTENSITY 100           // 0-100
#define DEFAULT_GRAIN_PRISM_ONLY 0            // false
#define DEFAULT_GRAIN_BRIGHTNESS_THRESHOLD 30 // 0-100

// =================================================================================================
// Main
// =================================================================================================

static void print_usage(const char *program) {
  fprintf(stderr, "Usage: %s <time> <resolution> <output.png>\n", program);
  fprintf(stderr, "  time: Time in H:MM or HH:MM format (e.g., 7:14 or 10:30)\n");
  fprintf(stderr, "  resolution: Image size in pixels (e.g., 4096)\n");
  fprintf(stderr, "  output.png: Output filename\n");
  fprintf(stderr, "\nExample: %s 7:14 4096 watchface.png\n", program);
}

static int parse_time(const char *time_str, int *hour, int *minute) {
  char *colon = strchr(time_str, ':');
  if (!colon)
    return 0;

  *hour = atoi(time_str);
  *minute = atoi(colon + 1);

  if (*hour < 0 || *hour > 23)
    return 0;
  if (*minute < 0 || *minute > 59)
    return 0;

  return 1;
}

int main(int argc, char *argv[]) {
  if (argc != 4) {
    print_usage(argv[0]);
    return 1;
  }

  // Parse arguments
  int hour, minute;
  if (!parse_time(argv[1], &hour, &minute)) {
    fprintf(stderr, "Error: Invalid time format '%s'\n", argv[1]);
    print_usage(argv[0]);
    return 1;
  }

  int resolution = atoi(argv[2]);
  if (resolution < 64 || resolution > 16384) {
    fprintf(stderr, "Error: Resolution must be between 64 and 16384\n");
    return 1;
  }

  const char *output_path = argv[3];

  // Allocate framebuffers
  int width = resolution;
  int height = resolution;
  size_t pixel_count = (size_t)width * height;

  float *float_fb = (float *)malloc(pixel_count * 4 * sizeof(float));
  uint8_t *fb = (uint8_t *)malloc(pixel_count * 4);

  if (!float_fb || !fb) {
    fprintf(stderr, "Error: Failed to allocate memory for %dx%d framebuffer\n", width, height);
    free(float_fb);
    free(fb);
    return 1;
  }

  // Calculate watch geometry
  float cx = (float)width / 2.0f;
  float cy = (float)height / 2.0f;
  float radius = (float)(width < height ? width : height) / 2.0f - 1.0f;

  // Create prism
  float prism_size = (DEFAULT_PRISM_SIZE / 100.0f) * radius;
  Prism prism;
  create_prism(cx, cy, prism_size, 60.0f, &prism);

  // Calculate time angles
  int hour12 = hour % 12;
  float minute_f = (float)minute;

  float minute_angle = ANGLE_0 + (minute_f / 60.0f) * TAU;
  float entry_x = cx + cosf_approx(minute_angle) * radius;
  float entry_y = cy + sinf_approx(minute_angle) * radius;

  float hour_angle = ANGLE_0 + ((float)hour12 / 12.0f) * TAU + (minute_f / 60.0f) * HOUR_ARC;

  // Calculate prism color (gray with blue tint) - must match renderer.ts formula
  int gray = DEFAULT_PRISM_GRAY;
  int blue_tint = DEFAULT_PRISM_BLUE_TINT;
  uint8_t prism_r = (uint8_t)(gray > blue_tint ? gray - blue_tint : 0);
  uint8_t prism_g = (uint8_t)(gray > blue_tint / 2 ? gray - blue_tint / 2 : 0);
  uint8_t prism_b = (uint8_t)gray;

  // Render with transparent background
  printf("Rendering %d:%02d at %dx%d...\n", hour, minute, width, height);

  render_watchface_scene(
      float_fb, fb, width, height, cx, cy, radius, entry_x, entry_y, hour_angle,
      DEFAULT_RAINBOW_SPREAD / 100.0f, &prism, DEFAULT_SHOW_MARKERS, prism_r, prism_g, prism_b,
      DEFAULT_PRISM_GLOW_WIDTH / 100.0f, DEFAULT_PRISM_GLOW_INTENSITY / 100.0f,
      DEFAULT_PRISM_GLOW_FALLOFF, DEFAULT_RAY_GLOW_WIDTH / 100.0f * radius,
      DEFAULT_RAY_GLOW_INTENSITY / 100.0f, DEFAULT_RAY_GLOW_FALLOFF, DEFAULT_MARKER_LENGTH / 100.0f,
      DEFAULT_MARKER_GLOW_WIDTH / 100.0f, DEFAULT_MARKER_GLOW_INTENSITY / 100.0f,
      DEFAULT_MARKER_GLOW_FALLOFF, DEFAULT_GRAIN_INTENSITY / 100.0f,
      1.0f, // grain_scale (no DPR scaling for export)
      DEFAULT_GRAIN_PRISM_ONLY, DEFAULT_GRADIENT_FILL,
      0, // vignette (disabled for transparent export)
      DEFAULT_PALETTE, DEFAULT_REVERSE_SPECTRUM, DEFAULT_GRAIN_BRIGHTNESS_THRESHOLD / 100.0f,
      1,    // transparent_background
      0,    // dither_enabled (disabled for PNG export)
      0,    // palette_mode (IDEAL, unused when dithering disabled)
      0.5f, // palette_saturation (unused when dithering disabled)
      0.2f, // dither_strength (default, unused when disabled)
      0,    // dither_kernel (ATKINSON, unused when disabled)
      0,    // dither_oklab_error (unused when disabled)
      0.0f, // dither_bw_threshold (unused when disabled)
      1.0f  // dither_chroma_weight (default, unused when disabled)
  );

  // Write PNG
  printf("Writing %s...\n", output_path);
  int result = stbi_write_png(output_path, width, height, 4, fb, width * 4);

  free(float_fb);
  free(fb);

  if (!result) {
    fprintf(stderr, "Error: Failed to write PNG file\n");
    return 1;
  }

  printf("Done!\n");
  return 0;
}
