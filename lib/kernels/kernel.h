#pragma once

// =================================================================================================
// Kernel Interface
// =================================================================================================
// Post-processing kernels operate on framebuffers. Each kernel is a pluggable module
// that can transform pixel data (gamma correction, grain, dithering, vignette, etc.)
//
// Memory ownership:
// - Framebuffer is owned by the caller
// - Kernels never allocate memory; caller provides any required caches
// - Config structs are passed by const pointer (kernel copies what it needs)

// -------------------------------------------------------------------------------------------------
// Kernel Function Signature
// -------------------------------------------------------------------------------------------------
// All kernels take:
//   - fb: linear RGBA framebuffer (float[width * height * 4])
//   - width, height: framebuffer dimensions
//   - config: kernel-specific configuration (cast to appropriate type)
//   - cache: optional caller-owned cache for kernel state (NULL if not needed)
//
// Kernels modify fb in-place.

typedef void (*KernelFn)(float *fb, int width, int height, const void *config, const void *cache);

// -------------------------------------------------------------------------------------------------
// Kernel Descriptor
// -------------------------------------------------------------------------------------------------
// Used for pipeline registration and introspection.

typedef struct {
  const char *name; // Human-readable name (e.g., "gamma", "grain")
  KernelFn apply;   // The kernel function
} Kernel;

// -------------------------------------------------------------------------------------------------
// Falloff Types (shared across kernels)
// -------------------------------------------------------------------------------------------------

typedef enum {
  FALLOFF_LINEAR = 0,
  FALLOFF_QUADRATIC = 1,
  FALLOFF_CUBIC = 2,
  FALLOFF_EXPONENTIAL = 3
} FalloffType;
