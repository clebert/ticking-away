#include <pebble.h>

// Implemented in the Zig render core (bin/pebble/render.zig), linked in as
// libwatchface.a. Fills `out` with one GColor8 byte per pixel for strip
// `band_index`; strips must be requested top-to-bottom because the dither
// carries error downward between them.
extern void pebbleRenderBand(uint8_t *out, uint16_t band_index, uint8_t hour, uint8_t minute);

static Window *s_window;
static Layer *s_canvas;

static void canvas_update_proc(Layer *layer, GContext *ctx) {
  GBitmap *fb = graphics_capture_frame_buffer(ctx);
  if (!fb) return;

  time_t now = time(NULL);
  struct tm *t = localtime(&now);
  uint8_t hour = t->tm_hour;
  uint8_t minute = t->tm_min;

  // One strip of GColor8 (band_height = 1; the render core is fixed at 260 wide).
  static uint8_t band[260];
  GRect bounds = gbitmap_get_bounds(fb);

  for (int y = bounds.origin.y; y < bounds.origin.y + bounds.size.h; y++) {
    pebbleRenderBand(band, (uint16_t)y, hour, minute);

    // gabbro's framebuffer is a regular rectangular 8-bit buffer, but go through
    // the row info so the same loop also holds on packed-circular formats.
    GBitmapDataRowInfo row = gbitmap_get_data_row_info(fb, y);

    for (int x = row.min_x; x <= row.max_x; x++) {
      row.data[x] = band[x];
    }
  }

  graphics_release_frame_buffer(ctx, fb);
}

static void tick_handler(struct tm *tick_time, TimeUnits units_changed) {
  layer_mark_dirty(s_canvas);
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);

  s_canvas = layer_create(layer_get_bounds(root));
  layer_set_update_proc(s_canvas, canvas_update_proc);
  layer_add_child(root, s_canvas);
}

static void window_unload(Window *window) {
  layer_destroy(s_canvas);
}

static void init(void) {
  s_window = window_create();

  window_set_window_handlers(s_window, (WindowHandlers){
    .load = window_load,
    .unload = window_unload,
  });

  window_stack_push(s_window, true);
  tick_timer_service_subscribe(MINUTE_UNIT, tick_handler);
}

static void deinit(void) {
  window_destroy(s_window);
}

int main(void) {
  init();
  app_event_loop();
  deinit();
}
