# Pebble Round 2 Port Plan

Port the Dark Side of the Moon watchface to the Pebble Round 2 (rePebble) smartwatch, reusing the
existing Zig rendering pipeline with a thin C app shell.

## Target Hardware

| Attribute         | Value                                |
| ----------------- | ------------------------------------ |
| Platform codename | Gabbro                               |
| Display           | 1.3" color e-paper, always-on, round |
| Resolution        | 260 x 260 pixels                     |
| Colors            | 64 (GColor8: 2 bits per channel)     |
| Processor         | Star-MC1 @ 240 MHz (Cortex-M33)      |
| Price / Ship      | $199, May 2026                       |

## Architecture

Same approach as `bin/inky-pico/`: a thin platform shell that calls into the shared Zig rendering
library (`lib/`), producing a normal installable `.pbw` watchface.

```
┌─────────────────────────────────┐
│  C App Shell (main.c)           │
│  - Pebble lifecycle (Window)    │
│  - TickTimerService             │
│  - Framebuffer capture/release  │
└──────────┬──────────────────────┘
           │ C ABI call
┌──────────▼──────────────────────┐
│  Zig Rendering Library          │
│  - Watchface.render() per band  │
│  - Dither to Pebble palette     │
│  - Write GColor8 to row buffer  │
└─────────────────────────────────┘
```

## Pixel Format: GColor8

Single byte per pixel: `AARRGGBB` (2 bits per channel).

```
Bit 7-6: Alpha (0b11 = opaque)
Bit 5-4: Red   (0-3)
Bit 3-2: Green (0-3)
Bit 1-0: Blue  (0-3)
```

Channel values 0-3 map to sRGB 0, 85, 170, 255. Full opaque prefix is `0xC0`.

## Framebuffer Access

Pebble exposes direct framebuffer writes inside a layer's `update_proc` callback:

```c
static void canvas_update_proc(Layer *layer, GContext *ctx) {
    GBitmap *fb = graphics_capture_frame_buffer(ctx);
    if (!fb) return;

    GRect bounds = gbitmap_get_bounds(fb);

    for (int y = bounds.origin.y; y < bounds.origin.y + bounds.size.h; y++) {
        // Round displays have variable-width rows (circular clip per scanline)
        GBitmapDataRowInfo row = gbitmap_get_data_row_info(fb, y);

        for (int x = row.min_x; x <= row.max_x; x++) {
            row.data[x] = /* GColor8 byte */;
        }
    }

    graphics_release_frame_buffer(ctx, fb);  // Must release before callback returns
}
```

Round display constraint: `gbitmap_get_bytes_per_row()` returns 0 on circular formats. Must use
`gbitmap_get_data_row_info()` per row to get valid pixel range.

## Rendering Pipeline Mapping

The existing band-by-band pipeline maps directly to framebuffer scanlines:

```
Watchface.render()  →  Image.Band(Linear)   [f32 RGBA per pixel]
        ↓
Dither.apply()      →  Image.Band(Srgb)     [u8 RGBA per pixel]
        ↓
Palette lookup      →  GColor8 byte         [AARRGGBB, 1 byte per pixel]
        ↓
Write to framebuffer row via gbitmap_get_data_row_info()
```

### Pebble Dither Palette

Create a Pebble-specific `Dither.Palette` using colors from the GColor8 gamut (channel values at 0,
85, 170, 255). Map palette indices to GColor8 bytes, similar to how the Pico maps to
`display_values`.

Note: the current `Dither.Palette` is hardcoded to `color_count = 6` for e-ink displays. It needs to
be generalized (or a new palette type created) to support a larger subset of the 64-color GColor8
gamut.

### sRGB to GColor8 Conversion

```zig
fn toGColor8(pixel: Srgb) u8 {
    const r: u8 = (pixel.r + 42) / 85;  // 0-3
    const g: u8 = (pixel.g + 42) / 85;
    const b: u8 = (pixel.b + 42) / 85;
    return 0xC0 | (r << 4) | (g << 2) | b;
}
```

With dithering active, palette indices map directly to pre-computed GColor8 values instead.

### Round Display Output

The round display's variable-width scanlines (`gbitmap_get_data_row_info()`) provide hardware
circular clipping — no software crop is needed (unlike the Inky Pico target which uses `Crop.zig`).

**Approach: render full rectangular bands, copy valid range.** The rendering pipeline runs unchanged
on a full 260px-wide band. The C shell then copies only the valid pixel range per scanline into the
framebuffer:

```c
// After rendering band into gcolor8_buffer[260 * band_height]:
for (int y = band_y; y < band_y + band_height; y++) {
    GBitmapDataRowInfo row = gbitmap_get_data_row_info(fb, y);
    int local_y = y - band_y;
    for (int x = row.min_x; x <= row.max_x; x++) {
        row.data[x] = gcolor8_buffer[local_y * 260 + x];
    }
}
```

At 260px width, the wasted pixels outside the circle are minimal (a few dozen per scanline at most).
This keeps the rendering library untouched — all clipping logic stays in the platform shell.

Alternative: pass per-row `[min_x, max_x]` clip bounds into the renderer to skip pixel computation
entirely. More efficient but requires threading variable-width bounds through `Watchface.render()`
and `Dither.apply()`, which currently assume rectangular bands. Only worth pursuing if rendering
time is tight.

## C App Shell

Minimal Pebble watchface lifecycle:

```c
#include <pebble.h>

static Window *s_window;
static Layer *s_canvas;

static void canvas_update_proc(Layer *layer, GContext *ctx) {
    GBitmap *fb = graphics_capture_frame_buffer(ctx);
    if (!fb) return;

    // TODO: Call Zig render function via C ABI
    // pebble_render(fb, hour, minute);

    graphics_release_frame_buffer(ctx, fb);
}

static void tick_handler(struct tm *tick_time, TimeUnits units) {
    layer_mark_dirty(s_canvas);
}

static void window_load(Window *window) {
    Layer *root = window_get_root_layer(window);
    GRect bounds = layer_get_bounds(root);
    s_canvas = layer_create(bounds);
    layer_set_update_proc(s_canvas, canvas_update_proc);
    layer_add_child(root, s_canvas);
}

static void window_unload(Window *window) {
    layer_destroy(s_canvas);
}

int main(void) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
        .load = window_load,
        .unload = window_unload,
    });
    window_stack_push(s_window, true);
    tick_timer_service_subscribe(MINUTE_UNIT, tick_handler);
    app_event_loop();
    window_destroy(s_window);
}
```

## Zig C ABI Export

Expose a render function callable from C:

```zig
/// Renders the watchface into a Pebble framebuffer.
/// Called from the C app shell's update_proc with row pointers from
/// gbitmap_get_data_row_info().
export fn pebble_render(
    row_data: [*][*]u8,      // Array of row data pointers
    row_min_x: [*]i16,       // Array of min_x per row
    row_max_x: [*]i16,       // Array of max_x per row
    height: u16,
    hour: u8,
    minute: u8,
) callconv(.c) void {
    // Band-by-band rendering, writing GColor8 bytes per scanline
}
```

Alternative: pass the `GBitmap *` directly and call `gbitmap_get_data_row_info` from Zig via
imported C function pointers. Needs investigation into what's simpler.

## Build Integration

### Option A: Static Library (Preferred)

Cross-compile the Zig library to a static `.a` for ARM Cortex-M33 (`arm-none-eabi`), then link it
into the Pebble project's waf build.

```bash
zig build-lib -target arm-freestanding-eabi -mcpu=cortex_m33 \
    -O ReleaseFast lib/root.zig -femit-bin=libwatchface.a
```

Integrate into Pebble's `wscript` or link via `pebble build` flags. Needs investigation into how the
Pebble waf build supports external static libraries.

### Option B: Zig Builds Everything

Use `zig build` to compile both the Zig lib and the C shell, bypassing `pebble build`. Would require
replicating:

- Pebble SDK linker script
- Startup code and CRT
- Resource packaging into `.pbw` format
- App metadata (UUID, name, version)

More control but significantly more work. Only pursue if Option A proves too restrictive.

## Open Questions

- **Memory budget**: How much RAM is available for rendering buffers on Gabbro? At 260px width with
  `band_height = 1`, the per-band buffers total ~11 KB: Linear ~4 KB (260 × 16 bytes f32 RGBA), Srgb
  ~1 KB (260 × 4 bytes), and dither error buffer ~6 KB (260 × 3 channels × 2 rows × 4 bytes). Need
  to confirm available heap.
- **Render time**: At 240 MHz Cortex-M33, rendering 260 scanlines should be fast, but the `f32` math
  in the pipeline may be slow without an FPU. Cortex-M33 has optional FPU — need to confirm Gabbro
  has it enabled.
- **Pebble SDK linking**: How to add an external `.a` to the waf build. Check if `pebble` CLI or
  `wscript` supports `LDFLAGS` or extra link inputs.
- **Dither palette selection**: Choose optimal colors from the 64-color GColor8 gamut for the Dark
  Side of the Moon aesthetic. The rainbow needs good spectral coverage; the background needs deep
  blacks with subtle variation.
- **Gabbro emulator**: Confirm `pebble install --emulator gabbro` is available in the current SDK
  for testing before hardware ships.

## Resources

- Developer portal: https://developer.repebble.com/
- C SDK docs: https://developer.repebble.com/docs/c/
- Watchface tutorial: https://developer.repebble.com/tutorials/watchface-tutorial/part1/
- Framebuffer guide:
  https://developer.repebble.com/guides/graphics-and-animations/framebuffer-graphics/
- PebbleOS source: https://github.com/coredevices/PebbleOS
- C watchface tutorial repo: https://github.com/coredevices/c-watchface-tutorial
- Cloud IDE (zero setup): https://developer.repebble.com/sdk/cloud
- Hardware info: https://developer.repebble.com/guides/tools-and-resources/hardware-information/
