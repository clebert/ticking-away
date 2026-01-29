#include "pipeline.h"

// =================================================================================================
// Pipeline Implementation
// =================================================================================================

void pipeline_init(Pipeline *p) {
  p->count = 0;
  // Zero out entries for safety
  for (int i = 0; i < PIPELINE_MAX_EFFECTS; i++) {
    p->entries[i].effect = nullptr;
    p->entries[i].config = nullptr;
    p->entries[i].cache = nullptr;
  }
}

int pipeline_add_effect(Pipeline *p, const Effect *effect, const void *config, void *cache) {
  if (p->count >= PIPELINE_MAX_EFFECTS) {
    return -1; // Pipeline full
  }
  if (effect == nullptr) {
    return -1; // Invalid effect
  }

  PipelineEntry *entry = &p->entries[p->count];
  entry->effect = effect;
  entry->config = config;
  entry->cache = cache;
  p->count++;

  return 0; // Success
}

void pipeline_execute(const Pipeline *p, float *fb, int width, int height) {
  for (int i = 0; i < p->count; i++) {
    const PipelineEntry *entry = &p->entries[i];
    if (entry->effect != nullptr && entry->effect->apply != nullptr) {
      entry->effect->apply(fb, width, height, entry->config, entry->cache);
    }
  }
}
