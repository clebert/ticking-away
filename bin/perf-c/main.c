#define _POSIX_C_SOURCE 199309L

#include "effects/gamma.h"
#include "pipeline.h"
#include "quantize/direct.h"
#include "scene.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define WIDTH 5120
#define HEIGHT 5120
#define MAX_FRAMES 720

static double timespec_to_ms(struct timespec *ts) {
  return (double)ts->tv_sec * 1000.0 + (double)ts->tv_nsec / 1000000.0;
}

static double timespec_diff_ms(struct timespec *start, struct timespec *end) {
  return timespec_to_ms(end) - timespec_to_ms(start);
}

int main(int argc, char *argv[]) {
  // Parse frame count argument
  int total_frames = MAX_FRAMES;
  if (argc > 1) {
    total_frames = atoi(argv[1]);
    if (total_frames <= 0 || total_frames > MAX_FRAMES) {
      fprintf(stderr, "Usage: perf-c [frames]\n");
      fprintf(stderr, "  frames: number of frames to render (1-%d, default: %d)\n", MAX_FRAMES, MAX_FRAMES);
      return 1;
    }
  }

  // Pre-allocate buffers
  printf("Allocating buffers for %dx%d resolution...\n", WIDTH, HEIGHT);

  size_t pixel_count = (size_t)WIDTH * HEIGHT;
  float *float_buffer = malloc(pixel_count * 4 * sizeof(float));
  uint8_t *rgba_buffer = malloc(pixel_count * 4);
  double *frame_times = malloc((size_t)total_frames * sizeof(double));

  if (!float_buffer || !rgba_buffer || !frame_times) {
    fprintf(stderr, "Failed to allocate buffers\n");
    return 1;
  }

  // Initialize scene with default config
  Scene scene;
  scene_init(&scene, WIDTH, HEIGHT);

  // Timing
  printf("Running benchmark: %d frames...\n", total_frames);

  struct timespec start, end, frame_start, frame_end;

  clock_gettime(CLOCK_MONOTONIC, &start);

  for (int frame_idx = 0; frame_idx < total_frames; frame_idx++) {
    int hour = frame_idx / 60;
    int minute = frame_idx % 60;

    clock_gettime(CLOCK_MONOTONIC, &frame_start);

    scene_set_time(&scene, hour, (float)minute);
    scene_render_linear(&scene, float_buffer);

    // Pipeline: gamma correction only
    Pipeline pipeline;
    pipeline_init(&pipeline);
    pipeline_add_effect(&pipeline, &EFFECT_GAMMA, NULL, NULL);
    pipeline_execute(&pipeline, float_buffer, WIDTH, HEIGHT);

    // Direct output (no dithering)
    quantize_direct_apply(float_buffer, rgba_buffer, WIDTH, HEIGHT);

    clock_gettime(CLOCK_MONOTONIC, &frame_end);
    frame_times[frame_idx] = timespec_diff_ms(&frame_start, &frame_end);
  }

  clock_gettime(CLOCK_MONOTONIC, &end);

  // Compute statistics
  double min_ms = frame_times[0];
  double max_ms = frame_times[0];
  double sum_ms = 0.0;

  for (int i = 0; i < total_frames; i++) {
    if (frame_times[i] < min_ms)
      min_ms = frame_times[i];
    if (frame_times[i] > max_ms)
      max_ms = frame_times[i];
    sum_ms += frame_times[i];
  }

  double total_ms = timespec_diff_ms(&start, &end);
  double avg_ms = sum_ms / total_frames;
  double fps = 1000.0 / avg_ms;

  // Print results
  printf("\n=== Performance Results ===\n");
  printf("Resolution: %dx%d\n", WIDTH, HEIGHT);
  printf("Frames: %d\n", total_frames);
  printf("Total time: %.2f ms\n", total_ms);
  printf("Average: %.3f ms/frame (%.1f FPS)\n", avg_ms, fps);
  printf("Min: %.3f ms\n", min_ms);
  printf("Max: %.3f ms\n", max_ms);

  free(float_buffer);
  free(rgba_buffer);
  free(frame_times);

  return 0;
}
