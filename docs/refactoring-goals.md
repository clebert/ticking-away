# Refactoring Goals: Band-Based Rendering

Summary of architectural decisions from the lib2 migration, preserved for the Zig rewrite.

---

## Core Goals

1. **Band-based rendering** - Render image in horizontal strips (bands) instead of full framebuffer
2. **No emscripten dependency** - Pure WASM compatibility
3. **Embedded-friendly** - All memory caller-managed, no hidden allocations
4. **Clean separation of concerns** - Geometry stays in geometry, config is config, state is state

---

## Memory Model

- **All memory caller-managed** - Caller allocates, passes pointers, library writes to them
- **No internal malloc** - Suitable for embedded without heap
- **Static allocation macros** for convenience (e.g., `DEFINE_OUTPUT_STATE(name, max_width)`)
- **Explicit buffer ownership** - Caller owns all buffers, library borrows via pointers

---

## Type Separation

| Category    | Purpose                                        | Example                                      |
| ----------- | ---------------------------------------------- | -------------------------------------------- |
| **Config**  | Immutable parameters, set once                 | `GlowConfig`, `OutputConfig`                 |
| **State**   | Mutable data that persists across bands/frames | `OutputState` (dither error rows)            |
| **Context** | Per-band rendering parameters                  | `BandContext` (buffer, dimensions, y_offset) |
| **Frame**   | Per-frame computed data, shared by all bands   | `SceneFrame` (prism geometry, time, circle)  |

Rule: Types without functions go in `types.h`. Types with functions stay co-located with those
functions.

---

## Module Structure

```
geometry/     Pure math, no rendering knowledge
  segment     Line segment with distance queries
  prism       Prism geometry (vertices, edges)
  intersect   Ray-prism intersection

config/       Immutable configuration structs
  glow        Glow falloff enum + compute function
  output      Output mode (linear, dithered, etc.)
  [per-layer] Layer-specific configs

band/         Band rendering infrastructure
  context     BandContext (buffer + dimensions + scene reference)
  layer       BandLayer interface (begin_frame, render)
  effect      BandEffect interface (apply)
  renderer    Orchestrates layers + effects + output

layers/       Content producers (write to buffer)
  background  Solid/gradient background
  prism       The prism shape
  rays        Light rays through prism
  markers     Hour/minute markers

effects/      Post-processing (modify buffer in-place)
  gamma       Gamma correction
  grain       Film grain
  vignette    Edge darkening

draw/         Low-level drawing primitives
  pixel       Additive RGB blending
  line        Glow line rendering

output/       Final conversion (float RGB -> uint8)
  state       Error diffusion state for dithering
```

---

## Key Design Decisions

### No Alpha Channel

- RGB only (f32 per channel), no alpha
- Additive blending via `pixel_add()`, no `pixel_blend()`
- Simplifies pipeline, reduces memory

### Band Rendering Flow

```
begin_frame()           -- once per frame, all layers
for each band:
  for each layer:
    layer.render(ctx)   -- write to float RGB buffer
  for each effect:
    effect.apply(ctx)   -- modify float buffer in-place
  output_convert(ctx)   -- float RGB -> uint8 RGB/RGBA
end_frame()             -- cleanup
```

### Clipping Responsibility

- **draw/ module is pure** - knows nothing about prism geometry
- **Simple case** (markers): Caller pre-clips segment to circle before calling
  `line_draw_glow_band()`
- **Complex case** (rays): Layer does its own pixel iteration for geometry-aware clipping

### No Convenience Wrappers

- If caller can compose from existing functions, don't add a wrapper
- Example: No `line_draw_glow()` for uniform intensity - caller passes same value for start/end

### Function Visibility

- Only expose functions that have external consumers
- No private APIs in headers
- Every public function must have documented caller(s)

---

## What Gets Consolidated

Old lib/ duplicates → Single type:

- `RaysRGBLinear`, `GradientRGBLinear`, `DitherLinearRGB` → `ColorRGB`
- `scene.c/h` → `SceneFrame` (data only, no functions)
- `pipeline.c/h` → `BandRenderer`
- `layers/layer.h` → `BandLayer`
- `effects/effect.h` → `BandEffect`
- `layers/gradient.c` + `layers/ray_palette.c` → merged into rays layer

---

## Naming Conventions

- Enum values: Full type prefix (e.g., `GLOW_FALLOFF_LINEAR` for `GlowFalloff`)
- Functions: `module_operation()` (e.g., `segment_init()`, `band_context_contains_y()`)
- Types: PascalCase structs (e.g., `BandContext`, `ColorRGB`)
- Explicit integer sizing: `int32_t` not `int`

---

## Output Stage

Supports multiple output modes:

- **Linear** - Direct float-to-uint8 conversion
- **Error diffusion** - Floyd-Steinberg or Atkinson dithering (needs state between bands)
- **Ordered dithering** - Blue noise or Bayer (stateless)

For error diffusion, need 2 error row pointers for Atkinson (1 for Floyd-Steinberg).
