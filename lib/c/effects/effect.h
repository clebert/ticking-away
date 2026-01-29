#pragma once

// =================================================================================================
// Effect Interface
// =================================================================================================
// Post-processing effects operate on framebuffers. Each effect is a pluggable module
// that transforms pixel data in-place (gamma correction, grain, vignette, etc.)
//
// Memory ownership:
// - Framebuffer is owned by the caller
// - Effects never allocate memory; caller provides any required caches
// - Config structs are passed by const pointer (effect copies what it needs)

// -------------------------------------------------------------------------------------------------
// Effect Function Signature
// -------------------------------------------------------------------------------------------------
// All effects take:
//   - fb: linear RGBA framebuffer (float[width * height * 4])
//   - width, height: framebuffer dimensions
//   - config: effect-specific configuration (cast to appropriate type)
//   - cache: optional caller-owned cache for effect state (nullptr if not needed)
//
// Effects modify fb in-place.

typedef void (*EffectFn)(float *fb, int width, int height, const void *config, const void *cache);

// -------------------------------------------------------------------------------------------------
// Effect Descriptor
// -------------------------------------------------------------------------------------------------
// Used for pipeline registration and introspection.

typedef struct {
  const char *name; // Human-readable name (e.g., "gamma", "grain")
  EffectFn apply;   // The effect function
} Effect;
