#pragma once

// =================================================================================================
// Kernel Pipeline
// =================================================================================================
// Chains multiple kernels together for sequential execution on a framebuffer.
//
// The pipeline is stack-allocatable with a fixed maximum number of kernels.
// This ensures no dynamic memory allocation, making it suitable for embedded environments.
//
// Typical usage:
//   Pipeline pipeline;
//   pipeline_init(&pipeline);
//   pipeline_add_kernel(&pipeline, &KERNEL_GAMMA, NULL, NULL);
//   pipeline_add_kernel(&pipeline, &KERNEL_GRAIN, &grain_cfg, &grain_geom);
//   pipeline_add_kernel(&pipeline, &KERNEL_VIGNETTE, &vignette_cfg, &vignette_geom);
//   pipeline_execute(&pipeline, framebuffer, width, height);
//
// Memory ownership:
// - Pipeline struct: Caller-owned (stack or static allocation)
// - Framebuffer: Caller-owned (passed to execute)
// - Configs/caches: Caller-owned pointers, must remain valid during execute
//
// Note: Dithering is NOT a pipeline kernel because it converts float->uint8 (format conversion)
// rather than transforming floats in-place. Call kernel_dither_apply() after pipeline execution.

#include "kernels/kernel.h"

// -------------------------------------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------------------------------------

// Maximum number of kernels in a pipeline (stack-allocatable)
enum { PIPELINE_MAX_KERNELS = 8 };

// -------------------------------------------------------------------------------------------------
// Pipeline Entry
// -------------------------------------------------------------------------------------------------
// Stores a kernel with its associated config and cache pointers.

typedef struct {
  const Kernel *kernel; // Kernel descriptor (contains apply function)
  const void *config;   // Kernel-specific configuration (can be NULL)
  void *cache;          // Kernel-specific cache/geometry (can be NULL)
} PipelineEntry;

// -------------------------------------------------------------------------------------------------
// Pipeline Struct
// -------------------------------------------------------------------------------------------------
// Stack-allocatable pipeline that chains kernels for sequential execution.

typedef struct {
  PipelineEntry entries[PIPELINE_MAX_KERNELS];
  int count; // Number of kernels in the pipeline
} Pipeline;

// -------------------------------------------------------------------------------------------------
// Pipeline API
// -------------------------------------------------------------------------------------------------

// Initialize an empty pipeline.
// Must be called before adding kernels.
void pipeline_init(Pipeline *p);

// Add a kernel to the pipeline with its config and cache.
// Returns 0 on success, -1 if pipeline is full (count >= PIPELINE_MAX_KERNELS).
// The kernel, config, and cache pointers must remain valid until pipeline_execute() completes.
int pipeline_add_kernel(Pipeline *p, const Kernel *kernel, const void *config, void *cache);

// Execute all kernels in the pipeline sequentially.
// Each kernel transforms the framebuffer in-place.
// Kernels are executed in the order they were added.
void pipeline_execute(const Pipeline *p, float *fb, int width, int height);

// -------------------------------------------------------------------------------------------------
// Convenience: Get kernel count
// -------------------------------------------------------------------------------------------------

// Returns the number of kernels currently in the pipeline.
static inline int pipeline_count(const Pipeline *p) { return p->count; }
