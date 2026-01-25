// NOLINTBEGIN(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming)
// Enable POSIX.1b (1993) APIs for nanosleep() and other real-time extensions
#define _POSIX_C_SOURCE 199309L
// NOLINTEND(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming)

#include "config.h"
#include "display.h"
#include "draw/pixel.h"
#include "effects/gamma.h"
#include "layers/ray_palette.h"
#include "pack.h"
#include "pipeline.h"
#include "quantize/dither.h"
#include "quantize/dither_error.h"
#include "scene.h"
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum { WIDTH = 1600, HEIGHT = 1200 };
static const size_t FLOAT_FB_SIZE = (size_t)WIDTH * HEIGHT * 4 * sizeof(float);
static const size_t RGBA_FB_SIZE = (size_t)WIDTH * HEIGHT * 4;
enum { MAIN_PACKED_BUFFER_SIZE = 480000 };

// Helper macro to compute glow RGB from gray and blueTint values (matching HTML UI)
// Formula from src/renderer.ts:
//   r = max(0, gray - blueTint)
//   g = max(0, gray - blueTint/2)
//   b = gray
// NOLINTBEGIN(cppcoreguidelines-macro-usage)
#define GLOW_RGB_FROM_UI(gray, blue_tint)                                                          \
  .r = ((gray) > (blue_tint) ? (gray) - (blue_tint) : 0),                                          \
  .g = ((gray) > ((blue_tint) / 2) ? (gray) - ((blue_tint) / 2) : 0), .b = (gray)
// NOLINTEND(cppcoreguidelines-macro-usage)

static volatile sig_atomic_t running = 1;

static void signal_handler(int sig) {
  (void)sig;
  running = 0;
}

static void get_current_time(int *hour, int *minute) {
  time_t now = time(nullptr);
  const struct tm *tm_info = localtime(&now);
  *hour = tm_info->tm_hour % 12;
  *minute = tm_info->tm_min;
}

static void sleep_until_next_minute(void) {
  time_t now = time(nullptr);
  const struct tm *tm_info = localtime(&now);
  int seconds_remaining = 60 - tm_info->tm_sec;

  struct timespec ts;
  ts.tv_sec = seconds_remaining;
  ts.tv_nsec = 0;

  while (nanosleep(&ts, &ts) == -1 && running) {
  }
}

int main(void) {
  (void)signal(SIGINT, signal_handler);
  (void)signal(SIGTERM, signal_handler);

  float *float_fb = malloc(FLOAT_FB_SIZE);
  if (float_fb == nullptr) {
    (void)fputs("Failed to allocate float framebuffer\n", stderr);
    return 1;
  }

  uint8_t *rgba_fb = malloc(RGBA_FB_SIZE);
  if (rgba_fb == nullptr) {
    (void)fputs("Failed to allocate RGBA framebuffer\n", stderr);
    free(float_fb);
    return 1;
  }

  uint8_t *packed_left = malloc(MAIN_PACKED_BUFFER_SIZE);
  if (packed_left == nullptr) {
    (void)fputs("Failed to allocate left packed buffer\n", stderr);
    free(rgba_fb);
    free(float_fb);
    return 1;
  }

  uint8_t *packed_right = malloc(MAIN_PACKED_BUFFER_SIZE);
  if (packed_right == nullptr) {
    (void)fputs("Failed to allocate right packed buffer\n", stderr);
    free(packed_left);
    free(rgba_fb);
    free(float_fb);
    return 1;
  }

  InkyDisplay display;
  if (inky_init(&display) < 0) {
    (void)fputs("Failed to initialize display (not running on Pi?)\n", stderr);
    free(packed_right);
    free(packed_left);
    free(rgba_fb);
    free(float_fb);
    return 1;
  }

  Scene scene;
  scene_init(&scene, WIDTH, HEIGHT);

  PrismConfig prism_cfg = {.size = 0.9f, .rainbow_spread = 0.5f};
  scene_set_prism_config(&scene, &prism_cfg);

  // Use GLOW_RGB_FROM_UI(gray, blueTint) to match HTML UI settings
  GlowConfig glow_cfg = {GLOW_RGB_FROM_UI(255, 100), .width = 0.05f, .intensity = 1.0f,
                         .falloff = FALLOFF_EXPONENTIAL};

  scene_set_glow_config(&scene, &glow_cfg);

  RayConfig ray_cfg = {.glow_width = 0.01f,
                       .intensity = 1.0f,
                       .falloff = FALLOFF_QUADRATIC,
                       .palette = RAY_PALETTE_SPECTRA6,
                       .gradient_fill = 1,
                       .reverse = 1};

  scene_set_ray_config(&scene, &ray_cfg);

  MarkerConfig marker_cfg = {.visible = 0,
                             .length = 0.1f,
                             .glow_width = 0.01f,
                             .glow_intensity = 1.0f,
                             .falloff = FALLOFF_QUADRATIC};

  scene_set_marker_config(&scene, &marker_cfg);

  DITHER_ERROR_CACHE_STATIC(dither_cache, 6, WIDTH);

  DitherErrorConfig dither_cfg = {.palette = DITHER_PALETTE_SPECTRA6_EPDOPT,
                                  .palette_count = DITHER_PALETTE_SPECTRA6_EPDOPT_COUNT,
                                  .algorithm = DITHER_FLOYD_STEINBERG,
                                  .strength = 0.75f,
                                  .oklab_error = 0,
                                  .chroma_weight = 4.0f};

  (void)puts("Inky watchface started. Press Ctrl+C to exit.");

  while (running) {
    int hour;
    int minute;
    get_current_time(&hour, &minute);

    (void)printf("Rendering time %02d:%02d...\n", hour, minute);

    scene_set_time(&scene, hour, (float)minute);

    scene_render_linear(&scene, float_fb);

    Pipeline pipeline;
    pipeline_init(&pipeline);
    (void)pipeline_add_effect(&pipeline, &EFFECT_GAMMA, nullptr, nullptr);
    pipeline_execute(&pipeline, float_fb, WIDTH, HEIGHT);

    if (dither_error_apply(float_fb, rgba_fb, WIDTH, HEIGHT, &dither_cfg, &dither_cache) < 0) {
      (void)fputs("Dithering failed\n", stderr);
      break;
    }

    pack_for_display(rgba_fb, DITHER_PALETTE_SPECTRA6_INKY, DITHER_PALETTE_SPECTRA6_INKY_COUNT,
                     packed_left, packed_right, WIDTH, HEIGHT);

    (void)puts("Sending to display (refresh takes ~32 seconds)...");

    if (inky_show(&display, packed_left, packed_right) < 0) {
      (void)fputs("Display update failed\n", stderr);
      break;
    }

    (void)puts("Display updated. Sleeping until next minute...");
    sleep_until_next_minute();
  }

  (void)puts("Shutting down...");

  inky_cleanup(&display);
  free(packed_right);
  free(packed_left);
  free(rgba_fb);
  free(float_fb);

  return 0;
}
