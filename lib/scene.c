// =================================================================================================
// Scene Implementation
// =================================================================================================
// High-level scene composition using the layer abstraction. The Scene struct holds all state
// needed to render a complete frame, and scene_render_linear() orchestrates the layers.

#include "scene.h"
#include "geometry/prism.h"
#include "kernels/kernel.h"
#include "layers/background.h"
#include "layers/gradient.h"
#include "layers/layer.h"
#include "layers/markers.h"
#include "layers/prism_glow.h"
#include "layers/rays.h"

// =================================================================================================
// Default Configuration Values
// =================================================================================================

// Prism defaults
#define DEFAULT_PRISM_SIZE 0.65f
#define DEFAULT_RAINBOW_SPREAD 0.5f
#define DEFAULT_BLUE_TINT 0.0f
#define DEFAULT_PRISM_GRAY 0.5f

// Glow defaults
#define DEFAULT_GLOW_R 128
#define DEFAULT_GLOW_G 128
#define DEFAULT_GLOW_B 128
#define DEFAULT_GLOW_WIDTH 0.15f
#define DEFAULT_GLOW_INTENSITY 0.6f
#define DEFAULT_GLOW_FALLOFF FALLOFF_QUADRATIC

// Ray defaults
#define DEFAULT_RAY_GLOW_WIDTH 0.025f
#define DEFAULT_RAY_INTENSITY 0.8f
#define DEFAULT_RAY_FALLOFF FALLOFF_QUADRATIC
#define DEFAULT_RAY_PALETTE 0
#define DEFAULT_RAY_GRADIENT_FILL 1
#define DEFAULT_RAY_REVERSE 0

// Marker defaults
#define DEFAULT_MARKER_VISIBLE 1
#define DEFAULT_MARKER_LENGTH 0.08f
#define DEFAULT_MARKER_GLOW_WIDTH 0.01f
#define DEFAULT_MARKER_GLOW_INTENSITY 0.7f
#define DEFAULT_MARKER_FALLOFF FALLOFF_QUADRATIC

// Prism apex angle (standard 60 degrees for equilateral triangle)
#define PRISM_APEX_ANGLE 60.0f

// =================================================================================================
// Initialization
// =================================================================================================

void scene_init(Scene *scene, int width, int height) {
  // Store dimensions
  scene->width = width;
  scene->height = height;

  // Compute circle geometry (watch face fits in the smaller dimension)
  int min_dim = width < height ? width : height;
  scene->radius = (float)min_dim / 2.0f;
  scene->cx = (float)width / 2.0f;
  scene->cy = (float)height / 2.0f;

  // Initialize time to 12:00
  scene->time_minutes = 0.0f;

  // Set default prism configuration
  scene->prism_config.size = DEFAULT_PRISM_SIZE;
  scene->prism_config.rainbow_spread = DEFAULT_RAINBOW_SPREAD;
  scene->prism_config.blue_tint = DEFAULT_BLUE_TINT;
  scene->prism_config.gray = DEFAULT_PRISM_GRAY;

  // Set default glow configuration
  scene->glow_config.r = DEFAULT_GLOW_R;
  scene->glow_config.g = DEFAULT_GLOW_G;
  scene->glow_config.b = DEFAULT_GLOW_B;
  scene->glow_config.width = DEFAULT_GLOW_WIDTH;
  scene->glow_config.intensity = DEFAULT_GLOW_INTENSITY;
  scene->glow_config.falloff = DEFAULT_GLOW_FALLOFF;

  // Set default ray configuration
  scene->ray_config.glow_width = DEFAULT_RAY_GLOW_WIDTH;
  scene->ray_config.intensity = DEFAULT_RAY_INTENSITY;
  scene->ray_config.falloff = DEFAULT_RAY_FALLOFF;
  scene->ray_config.palette = DEFAULT_RAY_PALETTE;
  scene->ray_config.gradient_fill = DEFAULT_RAY_GRADIENT_FILL;
  scene->ray_config.reverse = DEFAULT_RAY_REVERSE;

  // Set default marker configuration
  scene->marker_config.visible = DEFAULT_MARKER_VISIBLE;
  scene->marker_config.length = DEFAULT_MARKER_LENGTH;
  scene->marker_config.glow_width = DEFAULT_MARKER_GLOW_WIDTH;
  scene->marker_config.glow_intensity = DEFAULT_MARKER_GLOW_INTENSITY;
  scene->marker_config.falloff = DEFAULT_MARKER_FALLOFF;

  // Initialize palette caches (not yet valid)
  scene->rays_palette_cache.initialized = 0;
  scene->rays_palette_cache.palette = -1;
  scene->gradient_palette_cache.initialized = 0;
  scene->gradient_palette_cache.palette = -1;

  // Mark prism as needing computation
  scene->prism_dirty = 1;
}

// =================================================================================================
// Time Configuration
// =================================================================================================

void scene_set_time(Scene *scene, int hour, float minute) {
  // Wrap hour to [0, 11]
  hour = hour % 12;
  if (hour < 0)
    hour += 12;

  // Wrap minute to [0, 60)
  while (minute < 0.0f)
    minute += 60.0f;
  while (minute >= 60.0f)
    minute -= 60.0f;

  // Convert to total minutes
  scene->time_minutes = (float)hour * 60.0f + minute;
}

void scene_set_time_minutes(Scene *scene, float minutes) {
  // Wrap to [0, 720)
  while (minutes < 0.0f)
    minutes += 720.0f;
  while (minutes >= 720.0f)
    minutes -= 720.0f;

  scene->time_minutes = minutes;
}

// =================================================================================================
// Layer Configuration
// =================================================================================================

void scene_set_prism_config(Scene *scene, const PrismConfig *config) {
  scene->prism_config = *config;
  scene->prism_dirty = 1;
}

void scene_set_glow_config(Scene *scene, const GlowConfig *config) { scene->glow_config = *config; }

void scene_set_ray_config(Scene *scene, const RayConfig *config) {
  // Check if palette changed (invalidates cache)
  if (config->palette != scene->ray_config.palette) {
    scene->rays_palette_cache.initialized = 0;
    scene->gradient_palette_cache.initialized = 0;
  }
  scene->ray_config = *config;
}

void scene_set_marker_config(Scene *scene, const MarkerConfig *config) {
  scene->marker_config = *config;
}

// =================================================================================================
// Prism Management
// =================================================================================================

void scene_update_prism(Scene *scene) {
  // Compute prism size in pixels from fraction of radius
  float prism_size = scene->prism_config.size * scene->radius;

  // Create prism centered in watch face
  prism_create(scene->cx, scene->cy, prism_size, PRISM_APEX_ANGLE, &scene->prism);

  scene->prism_dirty = 0;
}

const Prism *scene_get_prism(const Scene *scene) { return &scene->prism; }

// =================================================================================================
// Rendering
// =================================================================================================

void scene_render_linear(Scene *scene, float *fb) {
  // Update prism if needed
  if (scene->prism_dirty) {
    scene_update_prism(scene);
  }

  // Build render context
  RenderContext ctx;
  ctx.fb = fb;
  ctx.width = scene->width;
  ctx.height = scene->height;
  ctx.cx = scene->cx;
  ctx.cy = scene->cy;
  ctx.radius = scene->radius;
  ctx.prism = &scene->prism;
  ctx.time_minutes = scene->time_minutes;
  ctx.prism_config = &scene->prism_config;
  ctx.glow_config = &scene->glow_config;
  ctx.ray_config = &scene->ray_config;
  ctx.marker_config = &scene->marker_config;

  // Initialize palette caches if needed
  rays_init_palette_cache(&scene->rays_palette_cache, scene->ray_config.palette);
  gradient_init_palette_cache(&scene->gradient_palette_cache, scene->ray_config.palette);

  // Render layers in order:
  // 1. Background - black circle with alpha mask
  layer_background_render(&ctx);

  // 2. Rays - entry ray, internal paths, exit rays, optional gradient fill
  layer_rays_render(&ctx);

  // 3. Prism glow - inner edge glow effect
  layer_prism_glow_render(&ctx);

  // 4. Markers - 12 hour markers (if visible)
  layer_markers_render(&ctx);
}
