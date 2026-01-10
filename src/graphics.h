#include "math.h"

// =================================================================================================
// Wavelength Constants
// =================================================================================================

// Visible spectrum wavelengths in nanometers: red (650nm) through violet (420nm)
#define NUM_WAVELENGTHS 8
static const float WAVELENGTHS[NUM_WAVELENGTHS] = {
  650.0f, 600.0f, 570.0f, 540.0f,
  510.0f, 480.0f, 450.0f, 420.0f
};

// =================================================================================================
// Wavelength to RGB
// =================================================================================================

typedef struct { uint8_t r, g, b; } RGB;

static RGB wavelength_to_rgb(float wavelength_nm) {
  float r = 0.0f, g = 0.0f, b = 0.0f;

  if (wavelength_nm >= 380.0f && wavelength_nm < 440.0f) {
    r = -(wavelength_nm - 440.0f) / 60.0f;
    b = 1.0f;
  } else if (wavelength_nm >= 440.0f && wavelength_nm < 490.0f) {
    g = (wavelength_nm - 440.0f) / 50.0f;
    b = 1.0f;
  } else if (wavelength_nm >= 490.0f && wavelength_nm < 510.0f) {
    g = 1.0f;
    b = -(wavelength_nm - 510.0f) / 20.0f;
  } else if (wavelength_nm >= 510.0f && wavelength_nm < 580.0f) {
    r = (wavelength_nm - 510.0f) / 70.0f;
    g = 1.0f;
  } else if (wavelength_nm >= 580.0f && wavelength_nm < 645.0f) {
    r = 1.0f;
    g = -(wavelength_nm - 645.0f) / 65.0f;
  } else if (wavelength_nm >= 645.0f && wavelength_nm <= 780.0f) {
    r = 1.0f;
  }

  float factor = 0.0f;
  if (wavelength_nm >= 380.0f && wavelength_nm < 420.0f) {
    factor = 0.3f + 0.7f * (wavelength_nm - 380.0f) / 40.0f;
  } else if (wavelength_nm >= 420.0f && wavelength_nm < 700.0f) {
    factor = 1.0f;
  } else if (wavelength_nm >= 700.0f && wavelength_nm <= 780.0f) {
    factor = 0.3f + 0.7f * (780.0f - wavelength_nm) / 80.0f;
  }

  RGB result;
  result.r = (uint8_t)(fast_powf(r * factor, 0.8f) * 255.0f);
  result.g = (uint8_t)(fast_powf(g * factor, 0.8f) * 255.0f);
  result.b = (uint8_t)(fast_powf(b * factor, 0.8f) * 255.0f);
  return result;
}

// =================================================================================================
// Pixel Operations
// =================================================================================================

static inline void set_pixel_additive(
  uint8_t* fb, int width, int height,
  int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  if (x < 0 || x >= width || y < 0 || y >= height) return;

  int idx = (y * width + x) * 4;
  uint32_t ar = (uint32_t)r * a / 255;
  uint32_t ag = (uint32_t)g * a / 255;
  uint32_t ab = (uint32_t)b * a / 255;

  uint32_t nr = (uint32_t)fb[idx] + ar;
  uint32_t ng = (uint32_t)fb[idx + 1] + ag;
  uint32_t nb = (uint32_t)fb[idx + 2] + ab;

  fb[idx] = nr > 255 ? 255 : (uint8_t)nr;
  fb[idx + 1] = ng > 255 ? 255 : (uint8_t)ng;
  fb[idx + 2] = nb > 255 ? 255 : (uint8_t)nb;
}

static inline void set_pixel_alpha(
  uint8_t* fb, int width, int height,
  int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  if (x < 0 || x >= width || y < 0 || y >= height) return;

  int idx = (y * width + x) * 4;

  if (a == 255) {
    fb[idx] = r;
    fb[idx + 1] = g;
    fb[idx + 2] = b;
    fb[idx + 3] = 255;
  } else {
    uint32_t alpha = a;
    uint32_t inv_alpha = 255 - a;
    fb[idx] = (uint8_t)((r * alpha + fb[idx] * inv_alpha) / 255);
    fb[idx + 1] = (uint8_t)((g * alpha + fb[idx + 1] * inv_alpha) / 255);
    fb[idx + 2] = (uint8_t)((b * alpha + fb[idx + 2] * inv_alpha) / 255);
    fb[idx + 3] = 255;
  }
}

// =================================================================================================
// Line Drawing (Bresenham)
// =================================================================================================

static void draw_line_additive(
  uint8_t* fb, int width, int height,
  int x0, int y0, int x1, int y1,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  int dx = x1 > x0 ? x1 - x0 : x0 - x1;
  int dy = y1 > y0 ? y1 - y0 : y0 - y1;
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx - dy;

  while (1) {
    set_pixel_additive(fb, width, height, x0, y0, r, g, b, a);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}

static void draw_line_alpha(
  uint8_t* fb, int width, int height,
  int x0, int y0, int x1, int y1,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  int dx = x1 > x0 ? x1 - x0 : x0 - x1;
  int dy = y1 > y0 ? y1 - y0 : y0 - y1;
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx - dy;

  while (1) {
    set_pixel_alpha(fb, width, height, x0, y0, r, g, b, a);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}

// =================================================================================================
// Circle Drawing (Midpoint Algorithm)
// =================================================================================================

static void draw_circle(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  int x = (int)(radius + 0.5f);
  int y = 0;
  int err = 0;
  int icx = (int)(cx + 0.5f);
  int icy = (int)(cy + 0.5f);

  while (x >= y) {
    set_pixel_alpha(fb, width, height, icx + x, icy + y, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx + y, icy + x, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx - y, icy + x, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx - x, icy + y, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx - x, icy - y, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx - y, icy - x, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx + y, icy - x, r, g, b, a);
    set_pixel_alpha(fb, width, height, icx + x, icy - y, r, g, b, a);

    if (err <= 0) {
      y++;
      err += 2 * y + 1;
    }
    if (err > 0) {
      x--;
      err -= 2 * x + 1;
    }
  }
}

// =================================================================================================
// Watch-Specific Drawing
// =================================================================================================

static void init_watch_framebuffer(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius
) {
  uint8_t bg_r = 35, bg_g = 35, bg_b = 35;
  uint8_t watch_r = 10, watch_g = 10, watch_b = 10;

  float r2 = radius * radius;

  for (int y = 0; y < height; y++) {
    float dy = (float)y - cy;
    float dy2 = dy * dy;
    int row_offset = y * width * 4;

    for (int x = 0; x < width; x++) {
      float dx = (float)x - cx;
      float dist2 = dx * dx + dy2;
      int idx = row_offset + x * 4;

      if (dist2 <= r2) {
        fb[idx] = watch_r;
        fb[idx + 1] = watch_g;
        fb[idx + 2] = watch_b;
      } else {
        fb[idx] = bg_r;
        fb[idx + 1] = bg_g;
        fb[idx + 2] = bg_b;
      }
      fb[idx + 3] = 255;
    }
  }
}

static void stroke_prism(
  uint8_t* fb, int width, int height,
  const Prism* prism,
  uint8_t r, uint8_t g, uint8_t b, uint8_t a
) {
  for (int i = 0; i < 3; i++) {
    int j = (i + 1) % 3;
    int x0 = (int)(prism->vertices[i * 2] + 0.5f);
    int y0 = (int)(prism->vertices[i * 2 + 1] + 0.5f);
    int x1 = (int)(prism->vertices[j * 2] + 0.5f);
    int y1 = (int)(prism->vertices[j * 2 + 1] + 0.5f);
    draw_line_alpha(fb, width, height, x0, y0, x1, y1, r, g, b, a);
  }
}

static int clip_segment_to_circle(
  float x0, float y0, float x1, float y1,
  float cx, float cy, float radius,
  float* out_x0, float* out_y0, float* out_x1, float* out_y1
) {
  float d0sq = (x0 - cx) * (x0 - cx) + (y0 - cy) * (y0 - cy);
  float d1sq = (x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy);
  float rsq = radius * radius;
  float tolerance = radius * 0.01f;
  float rsq_tol = (radius + tolerance) * (radius + tolerance);
  int p0_inside = d0sq <= rsq_tol;
  int p1_inside = d1sq <= rsq_tol;

  if (p0_inside && p1_inside) {
    *out_x0 = x0; *out_y0 = y0;
    *out_x1 = x1; *out_y1 = y1;
    return 1;
  }

  float dx = x1 - x0;
  float dy = y1 - y0;
  float fx = x0 - cx;
  float fy = y0 - cy;

  float a = dx * dx + dy * dy;
  float b = 2.0f * (fx * dx + fy * dy);
  float c = fx * fx + fy * fy - rsq;

  if (a < EPS_NORM) return 0;

  float discriminant = b * b - 4.0f * a * c;
  if (discriminant < 0.0f) {
    return 0;
  }

  float sqrt_disc = sqrtf_impl(discriminant);
  float t1 = (-b - sqrt_disc) / (2.0f * a);
  float t2 = (-b + sqrt_disc) / (2.0f * a);

  float t_start = 0.0f;
  float t_end = 1.0f;

  if (p0_inside && !p1_inside) {
    if (t2 > 0.0f && t2 <= 1.0f) {
      t_end = t2;
    } else {
      return 0;
    }
  } else if (!p0_inside && p1_inside) {
    if (t1 >= 0.0f && t1 < 1.0f) {
      t_start = t1;
    } else {
      return 0;
    }
  } else {
    if (t1 > 1.0f || t2 < 0.0f) {
      return 0;
    }
    t_start = t1 > 0.0f ? t1 : 0.0f;
    t_end = t2 < 1.0f ? t2 : 1.0f;
  }

  if (t_start >= t_end) return 0;

  *out_x0 = x0 + t_start * dx;
  *out_y0 = y0 + t_start * dy;
  *out_x1 = x0 + t_end * dx;
  *out_y1 = y0 + t_end * dy;
  return 1;
}

static void draw_watch_overlay(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius,
  float hour_x, float hour_y
) {
  draw_circle(fb, width, height, cx, cy, radius, 60, 60, 60, 255);

  float hour_angle_rad = atan2_approx(hour_y - cy, hour_x - cx);

  for (int h = 0; h < 12; h++) {
    float angle = ((float)h - 3.0f) * 30.0f * PI / 180.0f;

    float angle_diff = angle - hour_angle_rad;
    while (angle_diff > PI) angle_diff -= TAU;
    while (angle_diff < -PI) angle_diff += TAU;
    if (fabsf_impl(angle_diff) < 0.27f) continue;

    float inner_r = radius * 0.92f;
    float outer_r = radius * 0.98f;

    float cos_a = cosf_approx(angle);
    float sin_a = sinf_approx(angle);
    int x0 = (int)(cx + cos_a * inner_r + 0.5f);
    int y0 = (int)(cy + sin_a * inner_r + 0.5f);
    int x1 = (int)(cx + cos_a * outer_r + 0.5f);
    int y1 = (int)(cy + sin_a * outer_r + 0.5f);

    draw_line_alpha(fb, width, height, x0, y0, x1, y1, 100, 100, 100, 255);
  }
}

static void draw_chevron(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius,
  float hx, float hy
) {
  float scale = radius / 90.0f;
  if (scale < 0.5f) scale = 0.5f;

  float dx = cx - hx;
  float dy = cy - hy;
  float len = sqrtf_impl(dx * dx + dy * dy);
  if (len < EPS_NORM) {
    dx = 0.0f;
    dy = -1.0f;
  } else {
    dx /= len;
    dy /= len;
  }

  float px = -dy;
  float py = dx;

  float chev_length = 8.0f * scale;
  float chev_width = 5.0f * scale;
  float chev_offset = 2.0f * scale;

  float apex_x = hx + dx * (chev_offset + chev_length);
  float apex_y = hy + dy * (chev_offset + chev_length);
  float arm1_x = hx + dx * chev_offset + px * chev_width;
  float arm1_y = hy + dy * chev_offset + py * chev_width;
  float arm2_x = hx + dx * chev_offset - px * chev_width;
  float arm2_y = hy + dy * chev_offset - py * chev_width;

  int iapex_x = (int)(apex_x + 0.5f);
  int iapex_y = (int)(apex_y + 0.5f);
  int iarm1_x = (int)(arm1_x + 0.5f);
  int iarm1_y = (int)(arm1_y + 0.5f);
  int iarm2_x = (int)(arm2_x + 0.5f);
  int iarm2_y = (int)(arm2_y + 0.5f);

  draw_line_alpha(fb, width, height, iapex_x, iapex_y, iarm1_x, iarm1_y, 100, 100, 100, 255);
  draw_line_alpha(fb, width, height, iapex_x, iapex_y, iarm2_x, iarm2_y, 100, 100, 100, 255);
}

// =================================================================================================
// Watchface Rendering
// =================================================================================================

// Maximum spread in radians (30 degrees)
#define MAX_SPREAD_RAD (30.0f * PI / 180.0f)

// Internal fan spread factor (how much colors separate inside prism)
#define INTERNAL_FAN_FACTOR 0.15f

// Compute the exit angle for a given wavelength index.
// Returns angle that fans around the hour_angle based on spread.
static float compute_exit_angle(
  float hour_angle,
  float rainbow_spread,  // 0.0 to 1.0
  int wavelength_idx     // 0 = red, NUM_WAVELENGTHS-1 = violet
) {
  float spread_rad = rainbow_spread * MAX_SPREAD_RAD;

  // t: 0 for red (first), 1 for violet (last)
  float t = (float)wavelength_idx / (float)(NUM_WAVELENGTHS - 1);

  // Red bends least (toward positive offset), violet bends most (toward negative)
  // This mimics real dispersion where short wavelengths bend more
  float offset = (0.5f - t) * spread_rad;

  return hour_angle + offset;
}

// Render the watchface scene.
// - entry_x, entry_y: minute hand position (light source)
// - hour_angle: angle to hour position from center
// - rainbow_spread: 0.0 (no spread) to 1.0 (30 degree spread)
// - minimal_mode: if true, hide watch overlay (hour markers, chevron)
static void render_watchface_scene(
  uint8_t* fb, int width, int height,
  float cx, float cy, float radius,
  float entry_x, float entry_y,
  float hour_angle,
  float rainbow_spread,
  const Prism* prism,
  int minimal_mode
) {
  // Initialize background
  init_watch_framebuffer(fb, width, height, cx, cy, radius);

  // Entry ray direction: toward center
  float entry_dx = cx - entry_x;
  float entry_dy = cy - entry_y;
  vec2_normalize(&entry_dx, &entry_dy);

  // Find where entry ray hits prism
  RayHit prism_entry = find_prism_entry(entry_x, entry_y, entry_dx, entry_dy, prism);

  if (!prism_entry.hit) {
    // Ray doesn't hit prism - just draw overlay and return
    float hour_x = cx + cosf_approx(hour_angle) * radius;
    float hour_y = cy + sinf_approx(hour_angle) * radius;
    stroke_prism(fb, width, height, prism, 80, 80, 80, 200);
    if (!minimal_mode) {
      draw_watch_overlay(fb, width, height, cx, cy, radius, hour_x, hour_y);
      draw_chevron(fb, width, height, cx, cy, radius, hour_x, hour_y);
    }
    return;
  }

  // Draw white entry ray (from minute position to prism entry)
  {
    float clip_x0, clip_y0, clip_x1, clip_y1;
    if (clip_segment_to_circle(
      entry_x, entry_y, prism_entry.px, prism_entry.py,
      cx, cy, radius,
      &clip_x0, &clip_y0, &clip_x1, &clip_y1
    )) {
      draw_line_additive(fb, width, height,
        (int)(clip_x0 + 0.5f), (int)(clip_y0 + 0.5f),
        (int)(clip_x1 + 0.5f), (int)(clip_y1 + 0.5f),
        200, 200, 200, 255);
    }
  }

  // Draw colored rays (internal fan + exit rays)
  for (int i = 0; i < NUM_WAVELENGTHS; i++) {
    float wavelength = WAVELENGTHS[i];
    RGB color = wavelength_to_rgb(wavelength);

    // Compute exit angle for this wavelength
    float exit_angle = compute_exit_angle(hour_angle, rainbow_spread, i);

    // Find where exit ray (from center) exits the prism
    RayHit prism_exit = find_prism_exit_from_center(cx, cy, exit_angle, prism);

    if (prism_exit.hit) {
      // Internal path: from entry point to exit point (inside prism)
      // Apply slight internal fan for visual effect
      float internal_t = (float)i / (float)(NUM_WAVELENGTHS - 1);
      float internal_spread = rainbow_spread * INTERNAL_FAN_FACTOR * MAX_SPREAD_RAD;
      float internal_offset = (0.5f - internal_t) * internal_spread;

      // Adjust internal endpoint slightly based on wavelength
      float internal_exit_x = prism_exit.px + cosf_approx(exit_angle + PI/2) * internal_offset * 2.0f;
      float internal_exit_y = prism_exit.py + sinf_approx(exit_angle + PI/2) * internal_offset * 2.0f;

      // Internal gradient: white (like entry ray) to gray (prism color)
      // instead of showing rainbow colors inside the prism
      uint8_t white_r = 200, white_g = 200, white_b = 200;
      uint8_t gray_r = 80, gray_g = 80, gray_b = 80;
      uint8_t internal_r = (uint8_t)(white_r + internal_t * (gray_r - white_r));
      uint8_t internal_g = (uint8_t)(white_g + internal_t * (gray_g - white_g));
      uint8_t internal_b = (uint8_t)(white_b + internal_t * (gray_b - white_b));

      // Draw internal ray (entry to exit inside prism) with white-to-gray gradient
      draw_line_additive(fb, width, height,
        (int)(prism_entry.px + 0.5f), (int)(prism_entry.py + 0.5f),
        (int)(internal_exit_x + 0.5f), (int)(internal_exit_y + 0.5f),
        internal_r, internal_g, internal_b, 255);

      // Draw exit ray (from prism exit to circle edge) with actual rainbow color
      float exit_dir_x = cosf_approx(exit_angle);
      float exit_dir_y = sinf_approx(exit_angle);

      float border_x, border_y;
      if (ray_circle_intersection(
        prism_exit.px, prism_exit.py,
        exit_dir_x, exit_dir_y,
        cx, cy, radius,
        &border_x, &border_y
      )) {
        float clip_x0, clip_y0, clip_x1, clip_y1;
        if (clip_segment_to_circle(
          prism_exit.px, prism_exit.py, border_x, border_y,
          cx, cy, radius,
          &clip_x0, &clip_y0, &clip_x1, &clip_y1
        )) {
          draw_line_additive(fb, width, height,
            (int)(clip_x0 + 0.5f), (int)(clip_y0 + 0.5f),
            (int)(clip_x1 + 0.5f), (int)(clip_y1 + 0.5f),
            color.r, color.g, color.b, 255);
        }
      }
    }
  }

  // Draw prism outline
  stroke_prism(fb, width, height, prism, 80, 80, 80, 200);

  // Draw watch overlay (hour markers, chevron) unless minimal mode
  if (!minimal_mode) {
    float hour_x = cx + cosf_approx(hour_angle) * radius;
    float hour_y = cy + sinf_approx(hour_angle) * radius;
    draw_watch_overlay(fb, width, height, cx, cy, radius, hour_x, hour_y);
    draw_chevron(fb, width, height, cx, cy, radius, hour_x, hour_y);
  }
}
