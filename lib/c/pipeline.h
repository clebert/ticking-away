#pragma once

// =================================================================================================
// Effect Pipeline
// =================================================================================================
// Chains multiple effects together for sequential execution on a framebuffer.
//
// The pipeline is stack-allocatable with a fixed maximum number of effects.
// This ensures no dynamic memory allocation, making it suitable for embedded environments.
//
// Typical usage:
//   Pipeline pipeline;
//   pipeline_init(&pipeline);
//   pipeline_add_effect(&pipeline, &EFFECT_GAMMA, nullptr, nullptr);
//   pipeline_add_effect(&pipeline, &EFFECT_GRAIN, &grain_cfg, &grain_geom);
//   pipeline_add_effect(&pipeline, &EFFECT_VIGNETTE, &vignette_cfg, &vignette_geom);
//   pipeline_execute(&pipeline, framebuffer, width, height);
//
// Memory ownership:
// - Pipeline struct: Caller-owned (stack or static allocation)
// - Framebuffer: Caller-owned (passed to execute)
// - Configs/caches: Caller-owned pointers, must remain valid during execute
//
// Note: Dithering is NOT a pipeline effect because it converts float->uint8 (format conversion)
// rather than transforming floats in-place. Call quantize_dither_apply() after pipeline execution.

#include "effects/effect.h"

// -------------------------------------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------------------------------------

// Maximum number of effects in a pipeline (stack-allocatable)
enum { PIPELINE_MAX_EFFECTS = 8 };

// -------------------------------------------------------------------------------------------------
// Pipeline Entry
// -------------------------------------------------------------------------------------------------
// Stores an effect with its associated config and cache pointers.

typedef struct {
  const Effect *effect; // Effect descriptor (contains apply function)
  const void *config;   // Effect-specific configuration (can be nullptr)
  void *cache;          // Effect-specific cache/geometry (can be nullptr)
} PipelineEntry;

// -------------------------------------------------------------------------------------------------
// Pipeline Struct
// -------------------------------------------------------------------------------------------------
// Stack-allocatable pipeline that chains effects for sequential execution.

typedef struct {
  PipelineEntry entries[PIPELINE_MAX_EFFECTS];
  int count; // Number of effects in the pipeline
} Pipeline;

// -------------------------------------------------------------------------------------------------
// Pipeline API
// -------------------------------------------------------------------------------------------------

// Initialize an empty pipeline.
// Must be called before adding effects.
void pipeline_init(Pipeline *p);

// Add an effect to the pipeline with its config and cache.
// Returns 0 on success, -1 if pipeline is full (count >= PIPELINE_MAX_EFFECTS).
// The effect, config, and cache pointers must remain valid until pipeline_execute() completes.
int pipeline_add_effect(Pipeline *p, const Effect *effect, const void *config, void *cache);

// Execute all effects in the pipeline sequentially.
// Each effect transforms the framebuffer in-place.
// Effects are executed in the order they were added.
void pipeline_execute(const Pipeline *p, float *fb, int width, int height);

// -------------------------------------------------------------------------------------------------
// Convenience: Get effect count
// -------------------------------------------------------------------------------------------------

// Returns the number of effects currently in the pipeline.
static inline int pipeline_count(const Pipeline *p) { return p->count; }
