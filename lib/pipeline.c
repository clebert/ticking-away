#include "pipeline.h"

// =================================================================================================
// Pipeline Implementation
// =================================================================================================

void pipeline_init(Pipeline *p) {
  p->count = 0;
  // Zero out entries for safety
  for (int i = 0; i < PIPELINE_MAX_KERNELS; i++) {
    p->entries[i].kernel = 0;
    p->entries[i].config = 0;
    p->entries[i].cache = 0;
  }
}

int pipeline_add_kernel(Pipeline *p, const Kernel *kernel, const void *config, void *cache) {
  if (p->count >= PIPELINE_MAX_KERNELS) {
    return -1; // Pipeline full
  }
  if (kernel == 0) {
    return -1; // Invalid kernel
  }

  PipelineEntry *entry = &p->entries[p->count];
  entry->kernel = kernel;
  entry->config = config;
  entry->cache = cache;
  p->count++;

  return 0; // Success
}

void pipeline_execute(const Pipeline *p, float *fb, int width, int height) {
  for (int i = 0; i < p->count; i++) {
    const PipelineEntry *entry = &p->entries[i];
    if (entry->kernel != 0 && entry->kernel->apply != 0) {
      entry->kernel->apply(fb, width, height, entry->config, entry->cache);
    }
  }
}
