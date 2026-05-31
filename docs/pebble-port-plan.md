# Pebble Port Plan

Port the Dark Side of the Moon watchface to a Pebble smartwatch by reusing the Zig rendering
pipeline (`lib/`) behind a thin C app shell, producing a normal installable `.pbw` watchface.

> Hardware and SDK facts below were gathered on **2026-05-30**. The Pebble revival moves fast —
> treat ship dates and per-app memory numbers as provisional and re-verify against the sources at
> the bottom before committing engineering time.

## Starting point

The shipping targets are the **WebAssembly** module (`bin/wasm/`, the web demo) and the **PNG
export** binary (`bin/png/`). Two properties of the library make a Pebble port realistic:

- **Band-by-band rendering.** `lib/Image.zig`'s `Band`, with per-band `Watchface.render` /
  `Dither.apply` / `Crop.apply`, renders horizontal strips and carries Floyd–Steinberg error across
  band boundaries. This bounds peak memory, which is exactly what a Pebble port needs — see
  [Memory budget](#memory-budget).
- **Quantizing dither.** `lib/Dither.zig` maps a continuous image to the 64-colour Pebble palette in
  Oklab space with serpentine error diffusion; see [the Dither palette](#dither-palette).

`lib/frame.zig`'s `render()` renders the **full image as a single band**
(`image.band(Linear, buffer, image.height, 0)`), and both shells call it that way. Driving the
pipeline strip-by-strip on-device is therefore _new shell code_, not new library code — the banded
primitives already exist and are tested.

## Feasibility

**Feasible, with named risks.** The render algorithms carry over as-is; the work is bounded and the
approach has direct prior art.

### What the port involves

1. **A new `bin/pebble/` shell** — the standard Pebble C watchface lifecycle plus a small Zig C-ABI
   export wrapper (`callconv(.c)`), since the library exposes no C symbols today, only WASM
   `export fn`s.
2. **The Pebble dither palette** — `lib/Dither.zig` dithers to the fixed 64-colour `GColor8` cube.
   See [the Dither palette](#dither-palette).
3. **A Pebble-specific build of the library** — freestanding Thumb Cortex-M, **soft-float ABI**,
   position-independent code, linked into the Pebble app. See
   [Build integration](#build-integration).

### Why it's tractable

- `lib/frame.render()` is a **pure function over caller-provided buffers with no mutable globals**
  (the only global state lives in `bin/wasm/main.zig`, which is not ported). That is the favourable
  case for LLVM position-independent code on Pebble's load-everything-into-RAM app model.
- **Band rendering is mandatory and already exists**: a full-frame f32 linear RGBA buffer is ~1.08
  MB at 260×260 and won't fit the per-app budget or even SRAM.
- **Direct prior art** (see [Build integration](#build-integration)): `vsergeev/zig-pebble-sdk`
  builds Pebble watchfaces from Zig 0.16 — the toolchain this repo pins — targeting `emery` and
  `gabbro`; `andars/bits-of-rust` injected an LLVM-compiled PIC object into Pebble's `waf` link, a
  directly reusable hook for a Zig object.
- **It's testable in a simulator today, without hardware** — see
  [Testing without hardware](#testing-without-hardware).

### Risks to retire early, in order

1. Whether Zig 0.16 / LLVM emits relocations for `thumbv7m`/`thumbv7em` that the Pebble app loader
   applies correctly for any mutable globals/statics. Build a minimal Zig-on-Pebble proof first and
   keep global state at zero.
2. Soft-float f32 plus scalarized `@Vector` SIMD (≈59 uses across `lib/`; neither Cortex-M4F nor
   base Cortex-M33 has packed SIMD) — code size and render time within the budget. Fine in principle
   for a once-per-minute redraw, but must be measured on the emulator.
3. `compiler_rt` soft-float routines linking against newlib-nano without duplicate `__aeabi_*`
   symbols.

## Target hardware

The primary target is the round model — the circular Dark Side composition is a natural fit. The
rectangular 64-colour model is a straightforward second target.

| Attribute           | Pebble Round 2 (**primary**)                                                                                    | Pebble Time 2 (secondary)          |
| ------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| SDK platform name   | `gabbro`                                                                                                        | `emery`                            |
| Firmware board name | `getafix`                                                                                                       | `obelix`                           |
| Display             | 1.3" round 64-colour e-paper (reflective)                                                                       | 1.5" rectangular 64-colour e-paper |
| Resolution          | 260 × 260, ~200 DPI                                                                                             | 200 × 228, ~202 DPI                |
| Colours             | 64 (`GColor8`, 2 bits/channel)                                                                                  | 64 (`GColor8`)                     |
| SoC                 | SiFli SF32LB52J                                                                                                 | SiFli SF32LB52J                    |
| CPU                 | dual Cortex-M33 "STAR-MC1", 240 MHz + 24 MHz                                                                    | same                               |
| RAM                 | 512 KB SRAM (16 MB PSRAM **not yet enabled in PebbleOS**)                                                       | same                               |
| Price               | $199                                                                                                            | $225                               |
| Availability        | **Not yet shipping** (2026-05-30); production targeted late May, first units ~end of June, store says July 2026 | mass production since ~March 2026  |

Notes:

- The SoC is the **SiFli SF32LB52J**, a big.LITTLE pair of Cortex-M33 STAR-MC1 cores (240 MHz HCPU +
  24 MHz LCPU, 512 KB SRAM). The 16 MB PSRAM exists on-chip but is **not enabled in PebbleOS**, so
  don't count on it.
- Round 2 is **real and pre-orderable** (shown at CES, January 2026) but **has not shipped to
  customers**. Plan to validate entirely on the **emulator**.
- **FPU:** the Cortex-M33 FPU is optional and not confirmed for the SF32LB52J from primary sources —
  but it's **moot**, because the Pebble app ABI is soft-float regardless (see below).

### Platform names vs. board codenames

These are two different namespaces and easy to mix up:

- **SDK platform names** are what a _watchface_ compiles against and lists in `package.json`
  `targetPlatforms`: `gabbro` (Round 2), `emery` (Time 2), `flint` (Pebble 2 Duo, 144×168 B/W).
- **Firmware/hardware board codenames** (in `coredevices/PebbleOS`, `coredevices/hardware`):
  `getafix` (Round 2), `obelix` (Time 2), `asterix` (Pebble 2 Duo).

The watchface targets **`gabbro`/`emery`**, never `getafix`/`obelix`.

The legacy round platform is **`chalk`** (Pebble Time Round, 180×180). `gabbro` at 260×260 is
exactly twice the pixels and — importantly — uses a **different framebuffer format** (see
[Framebuffer access](#framebuffer-access)).

## Pebble app binary model (this drives everything)

A Pebble app is **not** a normal statically-linked ELF executable:

- The entire app — **code and static data** — loads into **RAM at a non-fixed address** as
  **position-independent, relocatable** code. At load time the firmware applies a relocation list
  and pokes a **syscall / symbol jump table** into the app so it can call firmware.
- There is **no full libc** — only a newlib-nano subset. Pebble functionality is reached through the
  jump table, not ordinary dynamic linking.
- The app ABI is **soft-float** (`-mfloat-abi=soft`) for cross-platform compatibility (the oldest
  supported platform, `aplite`, is an FPU-less Cortex-M3). All f32 math runs through `compiler_rt`
  soft-float **even on FPU-equipped silicon**, and `@Vector` ops scalarize.

Consequences for the Zig core:

- Build it `freestanding` for Thumb Cortex-M with `relocation-model=pic` and **soft-float**.
- Keep **mutable global/static state at zero** — the render core already qualifies; don't introduce
  any in the wrapper.
- Expect soft-float performance. For a once-per-minute redraw this is acceptable, but profile it.

<a id="memory-budget"></a>

## Memory budget: band rendering is mandatory

The per-app budget covers **code + static + heap + stack**, because the whole app lives in RAM.
Community figures (re-verify against PebbleOS headers): ~24 KB (`aplite`), 64 KB (`basalt`/`chalk`),
~128 KB (`emery`/`gabbro`).

A full-frame **f32 linear RGBA** scratch buffer does not fit anywhere:

- 260 × 260 × 16 B ≈ **1.08 MB** (`gabbro`)
- 200 × 228 × 16 B ≈ **730 KB** (`emery`)

…against a ~128 KB app budget and 512 KB total SRAM (PSRAM unavailable). So the renderer **must**
run strip-by-strip. With `band_height = 1` at 260 px wide, the per-band scratch is tiny:

| Buffer                                  | Size formula          | 260 px wide |
| --------------------------------------- | --------------------- | ----------- |
| Linear band (`lib.Linear`, f32)         | `width × 16 B`        | ~4.1 KB     |
| sRGB band (`lib.Srgb`, u8)              | `width × 4 B`         | ~1.0 KB     |
| Dither error (`Dither.errorBufferSize`) | `width × 3 × 2 × 4 B` | ~6.2 KB     |

The **framebuffer itself is owned by the firmware** — `graphics_capture_frame_buffer` hands you the
real 8-bit `GColor8` buffer (~66 KB for 260×260), which the OS already allocated. The app only pays
for the band scratch above, comfortably within budget.

`Dither.apply` carries pending error across band calls within a frame (the slot-0 invariant in
`lib/Dither.zig`), so strip rendering reproduces single-pass output bit-for-bit (proven by the
`multi-band dithering matches single-band dithering` test). Drive a few `band_height` values and
pick the smallest that renders fast enough.

## Pixel format: `GColor8`

Single byte per pixel, `AARRGGBB`, 2 bits per channel:

```
Bit 7-6: Alpha (0b11 = opaque)
Bit 5-4: Red   (0-3)
Bit 3-2: Green (0-3)
Bit 1-0: Blue  (0-3)
```

Channel values 0–3 expand to sRGB 0, 85, 170, 255. The opaque prefix is `0xC0`. The SDK's own
`GColorFromRGB(r, g, b)` macro quantizes each 0–255 channel by `>> 6` and sets alpha to opaque; it
is the live primary constructor (there is no `GColor8(r, g, b)` macro).

### sRGB → `GColor8`

For full-colour output, quantize each pixel. Rounding to the nearest of {0, 85, 170, 255} (the `+42`
trick) looks slightly better than the SDK macro's truncation:

```zig
fn toGColor8(pixel: lib.Srgb) u8 {
    const r: u8 = (pixel.r + 42) / 85; // 0-3, round-to-nearest
    const g: u8 = (pixel.g + 42) / 85;
    const b: u8 = (pixel.b + 42) / 85;
    return 0xC0 | (r << 4) | (g << 2) | b;
}
```

With dithering active the output is already exact cube colours, so this mapping is lossless — each
channel is one of {0, 85, 170, 255}, i.e. `>> 6` yields the 0–3 level directly.

<a id="dither-palette"></a>

### The Pebble dither palette

`lib/Dither.zig` dithers to **`pebble64`**: the fixed 64-colour `GColor8` cube (every channel ∈ {0,
85, 170, 255}). The Oklab Floyd–Steinberg and band error-diffusion run on-device as-is. The dither
path is exactly what the watchface needs:

- A single built-in palette (`pebble64`), so there is no palette selection — the renderer uses
  `Dither{ .palette = Dither.pebble64 }`. Index 0 is black, which `Dither.apply`'s background
  fast-path and `Palette.black()` rely on.
- Plain Euclidean Oklab nearest-colour and full Floyd–Steinberg error diffusion — no strength or
  chroma-emphasis knobs (with 64 colours those tunables made no useful visual difference).
- Oklab anchors derived from the palette's sRGB values via the standard sRGB transfer function. This
  is exactly emulator-accurate; on-hardware tuning would be a later, data-only refinement (see
  [Panel gamma](#panel-gamma)).
- Grain composes with the dither: it runs on the continuous image _before_ quantization
  (`Grain.applyLinear`), so the analog texture diffuses into the dither pattern.

The library emits `Srgb`, not `GColor8`. Mapping each dithered pixel to its `GColor8` byte is the
one remaining dither-side step and belongs in the Pebble shell's band loop — for the cube it is just
`>> 6` per channel (`0/85/170/255 → 0/1/2/3`) packed as `AARRGGBB`. The remaining port work is the
shell and the build.

## Framebuffer access

Inside a `Layer`'s `update_proc` you capture the framebuffer, write pixels, and release it before
returning:

```c
static void canvas_update_proc(Layer *layer, GContext *ctx) {
    GBitmap *fb = graphics_capture_frame_buffer(ctx);
    if (!fb) return;

    GRect bounds = gbitmap_get_bounds(fb);
    for (int y = bounds.origin.y; y < bounds.origin.y + bounds.size.h; y++) {
        GBitmapDataRowInfo row = gbitmap_get_data_row_info(fb, y);
        for (int x = row.min_x; x <= row.max_x; x++) {
            row.data[x] = /* GColor8 byte */;
        }
    }

    graphics_release_frame_buffer(ctx, fb); // must release before the callback returns
}
```

### Round displays: `gabbro` is rectangular, `chalk` is not

There are two distinct round-framebuffer situations:

- **`chalk`** (Pebble Time Round, 180×180) uses the packed **`GBitmapFormat8BitCircular`** format.
  There `gbitmap_get_bytes_per_row()` returns **0**, and each scanline has a different valid
  `[min_x, max_x]` range — the framebuffer literally omits the corner pixels.
- **`gabbro`** (Round 2, 260×260), despite being a round panel, uses a **regular rectangular
  `GBitmapFormat8Bit`** framebuffer (per the official Framebuffer Graphics guide). The round corners
  are masked by the physical bezel, not by the buffer format. `min_x`/`max_x` span the full
  260-pixel row.

The portable, branch-free pattern that works on **both** is to always go through
`gbitmap_get_data_row_info(fb, y)` and write only `[min_x, max_x]`. Don't assume a fixed
bytes-per-row stride, and don't special-case the shape in the renderer.

## Rendering pipeline mapping

The band pipeline maps cleanly onto framebuffer scanlines:

```
Watchface.render()  →  Image.Band(Linear)   [f32 RGBA per pixel, one strip]
        ↓
Dither.apply()      →  Image.Band(Srgb)      [u8 RGBA, quantized to the pebble64 palette]
   (or .toSrgb)         (dither error carried into the next strip)
        ↓
Crop.apply()        →  circular mask (optional; cosmetic on gabbro — bezel already masks)
        ↓
sRGB pixel  →  GColor8 byte (>> 6 per channel, AARRGGBB, 1 byte/pixel)
        ↓
write into framebuffer row via gbitmap_get_data_row_info()
```

`Crop.apply` (used by `frame.render` whenever `background_enabled`) is harmless on `gabbro` but
redundant — the bezel already hides the corners and the rectangular framebuffer has no
variable-width row to respect. Drop it for `gabbro` to save a pass, or keep it for parity with
rectangular targets and `chalk`.

## Zig C-ABI export wrapper

Add a wrapper (e.g. `bin/pebble/render.zig`) that mirrors `frame.render`'s caller-owns-the-buffers
convention but drives one strip per call so the C shell can blit it:

```zig
const lib = @import("lib");

const width = 260;
const band_height = 1;

// Frame-scoped scratch. Sized for a single strip; reused across bands.
var linear_buffer: [width * band_height]lib.Linear = undefined;
var srgb_buffer: [width * band_height]lib.Srgb = undefined;
var error_buffer: [lib.Dither.errorBufferSize(width)]f32 = undefined;

/// Renders strip `band_index` of the frame into `out` as GColor8 bytes.
/// Call bands in order 0..N within a frame so dither error diffuses correctly.
export fn pebbleRenderBand(
    out: [*]u8, // GColor8, width * band_height bytes
    band_index: u16,
    hour: u8,
    minute: u8,
) callconv(.c) void {
    // image.band(.., band_height, band_index) → Watchface.render
    // → Dither.apply (pebble64) → map each sRGB pixel to its GColor8 byte → out
}
```

Keeping the band scratch as fixed-size module data (rather than the heap) avoids allocator concerns
— just remember it counts against the app budget and **must not** introduce relocation surprises
(it's data, which is exactly what to test first). The C shell then loops `band_index` and copies
each strip into the framebuffer via `gbitmap_get_data_row_info`.

> Alternatives — importing `gbitmap_get_data_row_info` into Zig to write the framebuffer directly,
> or passing an array of row pointers — add C↔Zig callback complexity for no real gain. Prefer the C
> shell owning the framebuffer loop.

## C app shell

Standard Pebble watchface lifecycle:

```c
#include <pebble.h>

extern void pebbleRenderBand(uint8_t *out, uint16_t band_index, uint8_t hour, uint8_t minute);

static Window *s_window;
static Layer  *s_canvas;

static void canvas_update_proc(Layer *layer, GContext *ctx) {
    GBitmap *fb = graphics_capture_frame_buffer(ctx);
    if (!fb) return;

    time_t now = time(NULL);
    struct tm *t = localtime(&now);

    static uint8_t band[260]; // one strip of GColor8 (band_height = 1)
    GRect bounds = gbitmap_get_bounds(fb);
    for (int y = bounds.origin.y; y < bounds.origin.y + bounds.size.h; y++) {
        pebbleRenderBand(band, (uint16_t)y, t->tm_hour, t->tm_min);
        GBitmapDataRowInfo row = gbitmap_get_data_row_info(fb, y);
        for (int x = row.min_x; x <= row.max_x; x++) {
            row.data[x] = band[x];
        }
    }

    graphics_release_frame_buffer(ctx, fb);
}

static void tick_handler(struct tm *tick_time, TimeUnits units) {
    layer_mark_dirty(s_canvas);
}

static void window_load(Window *window) {
    Layer *root = window_get_root_layer(window);
    s_canvas = layer_create(layer_get_bounds(root));
    layer_set_update_proc(s_canvas, canvas_update_proc);
    layer_add_child(root, s_canvas);
}

static void window_unload(Window *window) { layer_destroy(s_canvas); }

int main(void) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
        .load = window_load, .unload = window_unload,
    });
    window_stack_push(s_window, true);
    tick_timer_service_subscribe(MINUTE_UNIT, tick_handler);
    app_event_loop();
    window_destroy(s_window);
}
```

## Build integration

### Toolchain

`pebble-tool` (the `pebble` CLI) is on PyPI / `coredevices/pebble-tool`. The arm-none-eabi toolchain
and QEMU are fetched by `pebble sdk install`, not bundled. The build system is `waf` + `wscript`
with `arm-none-eabi-gcc`; projects carry a `package.json` listing `sdkVersion` and `targetPlatforms`
(must include `gabbro`/`emery`).

```bash
# Node + uv are prerequisites
uv tool install pebble-tool --python 3.13
pebble sdk install latest        # pulls the arm-none-eabi toolchain + QEMU
pebble new-project myproject     # scaffold to copy package.json / wscript from
```

### Option A — inject a Zig object into the `waf` link

Compile the Zig library plus the export wrapper to a freestanding Thumb object/static lib, then hand
it to Pebble's `waf` build via `LINKFLAGS`. This is what `andars/bits-of-rust` did with an
LLVM-compiled `thumbv7m`, `relocation-model=pic` object — its `wscript` appends the object files to
`ctx.env.LINKFLAGS` rather than linking through Cargo. Reuse that hook for a Zig object:

```bash
# Per-platform -mcpu: cortex_m4 for flint, cortex_m33 for emery/gabbro.
zig build-lib lib/root.zig \
    -target thumb-freestanding-eabi -mcpu cortex_m33 \
    -fPIC -O ReleaseSmall -femit-bin=libwatchface.a
```

Then add the artifact to the app's link step in `wscript`. Confirm by reading the installed SDK's
`waftools` (e.g. `pebble_sdk_gcc.py`): the exact `-mcpu`/`-mthumb`, `-fPIC`/`-fPIE`,
`-mfloat-abi=soft`, and any `-msingle-pic-base` / `-mpic-register r9` the firmware loader expects,
so the Zig object's ABI and PIC model match the C objects byte-for-byte.

### Option B — drive everything from `build.zig`

`vsergeev/zig-pebble-sdk` (v1.3.0) builds Pebble watchfaces **entirely from Zig 0.16** — the Zig
version this repo pins in `build.zig.zon`. It injects the Pebble C API as a `pebble` import, uses
`callconv(.c)` callbacks, targets `emery` and `gabbro`, and emits a publishable `.pbw`. This is the
lowest-friction route: study its `build.zig` and adapt the `bin/pebble/` shell into its layout
rather than re-deriving the linker incantations by hand. Start here; fall back to Option A only if
its build model is too restrictive.

## Testing without hardware

The watchface can be built and run in a simulator today, for both colour targets, with no physical
watch — which matters because Round 2 hardware hasn't shipped.

The SDK ships a QEMU emulator (downloaded by `pebble sdk install`). SDK **4.9.127** added the QEMU
virtual platforms for the new hardware: `spalding_gabbro` (Round 2), `snowy_emery` (Time 2), and
`silk_flint` (Pebble 2 Duo). Workflow:

```bash
pebble build                          # emits the .pbw (Zig object linked in)
pebble install --emulator gabbro      # round 260x260; or: emery / basalt
pebble screenshot watchface.png       # capture the rendered frame
```

Use the documented `pebble install --emulator <platform>` form (some Core Devices posts write
`pebble install emulator --gabbro`; treat that as shorthand and verify against your installed
`pebble-tool` version).

Browser options:

- **CloudPebble** (`cloudpebble.repebble.com`) runs these emulators in-browser with zero install.
- **`ericmigi/pebble-qemu-wasm`** boots real PebbleOS firmware in the browser, but its machine set
  does **not** include `gabbro` (only `emery` is tested). For the **round** target use native QEMU
  (`pebble install --emulator gabbro`) or CloudPebble.

Recommended bring-up loop: get a trivial C-only watchface running in `--emulator gabbro` first; then
link in a minimal Zig object to retire the relocation risk; then wire in the real renderer
band-by-band and `pebble screenshot` to compare against the PNG export.

## Open questions

- **Exact app build flags.** Read the installed SDK `waftools` for the precise `-mcpu`, `-mthumb`,
  `-fPIC`/`-fPIE`, `-mfloat-abi=soft`, `-msingle-pic-base`/`-mpic-register` — don't infer the PIC
  model from ARM convention.
- **Relocations.** Empirically confirm Zig 0.16/LLVM emits data relocations the Pebble loader
  applies correctly for `thumbv7m`/`thumbv7em` under `relocation-model=pic`. Build a minimal proof
  first.
- **Performance & size.** Measure soft-float render time and `.pbw` code/heap size on the
  `gabbro`/`emery` emulator with `@Vector` ops scalarized, against the ~128 KB budget.
- **Linker hygiene.** Confirm `compiler_rt` soft-float routines link against newlib-nano with no
  duplicate `__aeabi_*` symbols.
- **Manifest.** Confirm the exact `sdkVersion` string and `targetPlatforms` list the appstore
  accepts for a 4.9.x watchface; re-read per-app heap numbers from PebbleOS headers.
- <a id="panel-gamma"></a>**Panel gamma — mostly resolved; not a blocker.** `GColor8` is a _nominal_
  colour space: levels expand linearly to {0, 85, 170, 255} (no gamma), and the QEMU emulator
  renders them linearly (`* 255 / 3`, no curve), so an sRGB-derived palette is **exactly**
  emulator-accurate. PebbleOS adds **no** gamma/colour-correction LUT for `getafix`/`obelix` — the
  SiFli driver (`src/fw/drivers/display/sf32lb/display_jdi.c`) only does a mechanical 222→332
  bit-repack (its LCDC layer is `RGB332`); the `GColor8`/ARGB2222 model is identical to
  `basalt`/`chalk`. The **only** residual unknown is the physical reflective JDI panel + the closed
  SiFli vendor HAL (`bf0_hal_lcdc.c`), measurable only on real hardware. If its response diverges
  from sRGB it degrades dither **quality** (mis-ranked nearest-colour, drifted error diffusion —
  most visible on the rainbow gradient), never output validity; the fix re-derives only the 64 Oklab
  anchors over the same verbatim `srgb_colors`. So it cannot gate pre-hardware work.
- **Shipping reality.** Confirm Round 2 hardware actually ships before relying on anything beyond
  the emulator.

## Resources

- Developer portal: https://developer.repebble.com/
- C SDK reference (colours):
  https://developer.repebble.com/docs/c/Graphics/Graphics_Types/Color_Definitions/
- Framebuffer graphics guide:
  https://developer.repebble.com/guides/graphics-and-animations/framebuffer-graphics/
- SDK 4.9.127 changelog (added `gabbro`/`emery`/`flint` QEMU):
  https://developer.repebble.com/sdk/changelogs/4.9.127
- CloudPebble + Round 2 SDK announcement:
  https://repebble.com/blog/cloudpebble-returns-plus-pure-javascript-and-round-2-sdk
- Pebble Round 2 announcement: https://repebble.com/blog/pebble-round-2-the-most-stylish-pebble-ever
- Store / current specs: https://repebble.com/watch
- PebbleOS source (maintained fork): https://github.com/coredevices/PebbleOS
- Hardware design files (board codenames): https://github.com/coredevices/hardware
- `pebble-tool` CLI: https://github.com/coredevices/pebble-tool
- Zig prior art — Pebble SDK from Zig 0.16: https://github.com/vsergeev/zig-pebble-sdk
- LLVM-object-into-waf prior art (Rust): https://github.com/andars/bits-of-rust
- SoC details (SiFli SF32LB52J):
  https://www.cnx-software.com/2025/05/14/sifli-sf32lb52j-big-little-arm-cortex-m33-bluetooth-mcu-powers-the-core-time-2-smartwatch/
- In-browser QEMU (no `gabbro`): https://github.com/ericmigi/pebble-qemu-wasm
