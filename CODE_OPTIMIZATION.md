# Code Optimization Tracking

Goal: Remove unnecessary code while maintaining readable, well-named, structured code.

## Baseline Metrics (2026-01-31)

| Metric        | Before   | After    | Change   |
| ------------- | -------- | -------- | -------- |
| Library lines | 3109     | 2805     | -304     |
| Test lines    | 1608     | 1562     | -46      |
| **Total**     | **4717** | **4367** | **-350** |

### Library Lines by Module (After)

| Module     | Lines |
| ---------- | ----- |
| dither     | 453   |
| rendering  | 463   |
| geometry   | 394   |
| pipeline   | 363   |
| color      | 339   |
| effects    | 193   |
| math       | 28    |
| root files | 572   |

---

## Optimization Log

| Date       | Change                                                                | Lines Removed |
| ---------- | --------------------------------------------------------------------- | ------------- |
| 2026-01-31 | Remove `band.Context.clear()`                                         | -4            |
| 2026-01-31 | Remove `ordered.apply()`, inline `BayerMatrix()`                      | -35           |
| 2026-01-31 | Remove `ErrorBuffer.init()/deinit()` (renamed `initStatic` to `init`) | -10           |
| 2026-01-31 | Make `vignette` defaults internal                                     | -3            |
| 2026-01-31 | Vectorize `gamma.applyToBuffer()` using @Vector clamp                 | 0             |
| 2026-01-31 | Use `@memcpy`/`@memset` for `ErrorBuffer.rotateRows()`                | -14           |
| 2026-01-31 | Use u32 writes in `postprocess.fillRowWithWhite()`                    | -2            |
| 2026-01-31 | Cache `inv_dist_range` in `vignette.apply()`                          | 0             |
| 2026-01-31 | Cache `inv_scale`, `r2`, hoist `gy` in `grain.apply()`                | +3            |
| 2026-01-31 | Extract `applyPostprocessAndOutput()` helper in pipeline              | -65           |
| 2026-01-31 | Remove unused imports from pipeline.zig                               | -5            |
| 2026-01-31 | Consolidate glow.renderLine calls in watchface.zig                    | -47           |
| 2026-01-31 | Make `output.floatToByte` internal (remove `pub`)                     | 0             |
| 2026-01-31 | Make `markers.outer_percent` internal (remove `pub`)                  | 0             |
| 2026-01-31 | Remove unused `Scene.setTimeMinutes()` function                       | -4            |
| 2026-01-31 | Consolidate `applyAtkinson`/`applyFloydSteinberg` into single `apply` | -99           |
| 2026-01-31 | Remove `Type = Palette` alias from palette.zig                        | -2            |
| 2026-01-31 | Simplify `applyDither` with labeled blocks and `orelse`               | -24           |
| 2026-01-31 | Unify `band_count` constant (clock re-exports from palette)           | +1            |

---

## Changes Made

### 1. `rendering/band.zig`

- Removed unused `clear()` method (only `clearWithBackground()` was used)

### 2. `dither/ordered.zig`

- Removed `apply()` function (index output variant) - only `applyRgba()` is used in production
- Made `getThreshold()` internal (removed `pub`)
- Inlined `BayerMatrix()` type function

### 3. `dither/error_diffusion.zig`

- Removed `init()` (allocator-based) and `deinit()` - production uses static buffers
- Renamed `initStatic()` to `init()` as the only initialization path

### 4. `effects/vignette.zig`

- Made `default_background` and `default_strength` internal (removed `pub`)
- Cache `inv_dist_range = 1.0 / (max_dist - radius)` for distance normalization

### 5. `effects/grain.zig`

- Cache `inv_scale = 1.0 / config.scale` for coordinate scaling
- Pre-compute `r2 = radius * radius` for circle masking
- Hoist `gy` computation outside inner x-loop

### 6. `color/gamma.zig`

- Vectorize `applyToBuffer()` using `@min`/`@max` on Color vectors

### 7. `pipeline/pipeline.zig`

- Extract `applyPostprocessAndOutput()` helper to consolidate duplicate post-processing logic
- Remove unused imports (`dither`, `error_diffusion`, `ordered`, `grain`, `vignette`, `boundary`)

### 8. `watchface.zig`

- Extract `base_config` for glow rendering to eliminate duplicate config structs
- Unify colored ray rendering (bounce→exit and direct path) into single code path
- Inline `line.Segment.init()` calls
- Remove unused `setTimeMinutes()` function

### 9. `pipeline/output.zig`

- Make `floatToByte()` internal (remove `pub`) - only used within module

### 10. `rendering/markers.zig`

- Make `outer_percent` internal (remove `pub`) - only used within module

### 11. `dither/error_diffusion.zig`

- Consolidate `applyAtkinson()` and `applyFloydSteinberg()` into unified `apply()` function
- Share quantization loop, pixel processing, and output writing
- Only diffusion pattern differs between algorithms (switch inside inner loop)

### 12. `color/palette.zig`

- Remove `Type = Palette` alias (use `Palette` directly per style guide)

### 13. `pipeline/postprocess.zig`

- Simplify `applyDither` using labeled blocks and `orelse` instead of nested if/else
- Single fallback to `output.writeRgba` instead of duplicated in each branch

### 14. `clock.zig`

- Re-export `band_count` from `palette` instead of duplicating the constant

---

## Entry Points

Production entry (wasm/main.zig):

```
renderWatchfaceWithConfig()
  └─ lib.pipeline.renderFrame()
       ├─ scene.renderBand() / renderBandWithGeometry()
       │    ├─ glow.renderLine() - ray rendering
       │    ├─ gradient.render() - spectrum fill
       │    ├─ glow.renderPrismEdges() - prism outline
       │    └─ markers rendering
       ├─ postprocess.apply()
       │    ├─ gamma.applyToBuffer()
       │    ├─ grain.apply()
       │    └─ vignette.apply()
       └─ postprocess.applyDither() or output.write()
            ├─ error_diffusion.apply()
            └─ ordered.applyRgba()
```

---

## Optimization Philosophy

**Goal**: Minimize lines while maintaining readability.

**DO**:

- Remove unused code and dead paths
- Extract shared logic into helpers to eliminate duplication
- Use clearer control flow (e.g., `const x = if (cond) a else b` instead of nested ifs)
- Pre-compute values outside loops when it makes the code clearer

**DON'T**:

- Add micro-optimizations that obscure intent (e.g., bit manipulation, SIMD intrinsics)
- Replace readable loops with clever one-liners
- Sacrifice clarity for marginal performance gains
- Add complexity just to avoid a division or function call

The code should be fast enough, but readability comes first.
