# Zig Codebase Refactoring Plan

## Overview

Reorganize the flat 28-file Zig codebase into a structured folder hierarchy with domain-appropriate
naming. The refactoring follows the design in [REFACTORING.md](REFACTORING.md).

**Key Changes:**

- Create 6 folders: `math/`, `geometry/`, `rendering/`, `color/`, `effects/`, `dither/`
- Rename types: `Triangle` → `Prism`, `Circle` → `Boundary`
- Rename files: `triangle.zig` → `prism.zig`, `circle.zig` → `boundary.zig`, etc.
- Move rendering logic from `band.zig` to `glow.zig` and `gradient.zig`

**Verification:** Run `npm run ci` after each phase to ensure build passes.

---

## Phase 1: Create Folder Structure

**Goal:** Create empty folders without moving any files.

**Tasks:**

```bash
mkdir -p lib/zig/math
mkdir -p lib/zig/geometry
mkdir -p lib/zig/rendering
mkdir -p lib/zig/color
mkdir -p lib/zig/effects
mkdir -p lib/zig/dither
```

**Exit Criteria:** Folders exist, `npm run ci` passes (no code changes).

**Handover Note:** Folders created, ready for file moves in Phase 2.

---

## Phase 2: Move Math & Color Modules

**Goal:** Move the simplest, most foundational modules with fewest dependents.

**Files to Move:** | From | To | |------|-----| | `lib/zig/vec2.zig` | `lib/zig/math/vec2.zig` | |
`lib/zig/range.zig` | `lib/zig/math/range.zig` | | `lib/zig/color.zig` | `lib/zig/color/color.zig` |
| `lib/zig/oklab.zig` | `lib/zig/color/oklab.zig` | | `lib/zig/gamma.zig` |
`lib/zig/color/gamma.zig` | | `lib/zig/palette.zig` | `lib/zig/color/palette.zig` |

**Import Updates Required:**

- `root.zig` - Update all 6 import paths
- Search all files for `@import("vec2.zig")` etc. and update to new paths

**Key Files to Update (vec2 importers):**

- band.zig, circle.zig, gradient.zig, grain.zig, intersect.zig, line.zig, markers.zig, ray.zig,
  scene.zig, spectrum.zig, triangle.zig, vignette.zig

**Key Files to Update (color importers):**

- band.zig, compat.zig, dither.zig, effect.zig, gamma.zig, grain.zig, markers.zig, oklab.zig,
  palette.zig, scene.zig, vignette.zig

**Exit Criteria:** `npm run ci` passes with new import paths.

**Handover Note:** Math and color modules moved. Remaining modules still at top level.

---

## Phase 3: Move Geometry Modules

**Goal:** Move geometry-related modules (keeping original names for now).

**Files to Move:** | From | To | |------|-----| | `lib/zig/triangle.zig` |
`lib/zig/geometry/triangle.zig` | | `lib/zig/circle.zig` | `lib/zig/geometry/circle.zig` | |
`lib/zig/line.zig` | `lib/zig/geometry/line.zig` | | `lib/zig/ray.zig` | `lib/zig/geometry/ray.zig`
| | `lib/zig/intersect.zig` | `lib/zig/geometry/intersect.zig` |

**Import Updates Required:**

- `root.zig` - Update 5 import paths
- **triangle.zig importers (8):** band.zig, clip.zig, grain.zig, gradient.zig, intersect.zig,
  scene.zig, spectrum.zig, root.zig
- **circle.zig importers (6):** clip.zig, intersect.zig, markers.zig, scene.zig, spectrum.zig,
  root.zig
- **line.zig importers:** band.zig, scene.zig, root.zig
- **ray.zig importers:** intersect.zig, spectrum.zig, root.zig
- **intersect.zig importers:** spectrum.zig, root.zig

**Test Files to Update:**

- `tests/triangle_test.zig` - Update import path
- `tests/line_test.zig` - Update import path
- `tests/band_test.zig` - Update triangle import
- `tests/spectrum_test.zig` - Update triangle, circle imports

**Exit Criteria:** `npm run ci` passes with geometry modules in new location.

**Handover Note:** Geometry modules moved to `geometry/`. Types still have old names (Triangle,
Circle).

---

## Phase 4: Move Rendering, Effects & Dither Modules

**Goal:** Move remaining module groups to their folders.

**Files to Move:** | From | To | |------|-----| | `lib/zig/band.zig` | `lib/zig/rendering/band.zig`
| | `lib/zig/glow.zig` | `lib/zig/rendering/glow.zig` | | `lib/zig/gradient.zig` |
`lib/zig/rendering/gradient.zig` | | `lib/zig/clip.zig` | `lib/zig/rendering/clip.zig` | |
`lib/zig/markers.zig` | `lib/zig/rendering/markers.zig` | | `lib/zig/effect.zig` |
`lib/zig/effects/effect.zig` | | `lib/zig/grain.zig` | `lib/zig/effects/grain.zig` | |
`lib/zig/vignette.zig` | `lib/zig/effects/vignette.zig` | | `lib/zig/dither.zig` |
`lib/zig/dither/dither.zig` | | `lib/zig/ordered_dither.zig` | `lib/zig/dither/ordered_dither.zig` |
| `lib/zig/error_diffusion.zig` | `lib/zig/dither/error_diffusion.zig` |

**Import Updates Required:**

- `root.zig` - Update 11 import paths
- Update all cross-references between moved modules
- `scene.zig`, `compat.zig` - Heavy importers of these modules

**Test Files to Update:**

- `tests/band_test.zig` - Update band, glow imports

**Exit Criteria:** `npm run ci` passes. All modules in folders. Only `spectrum.zig`, `clock.zig`,
`scene.zig`, `compat.zig`, `root.zig` remain at top level.

**Handover Note:** Folder structure complete. Ready for file renames in Phase 5.

---

## Phase 5: Rename Files

**Goal:** Rename files to match their domain purpose (without changing type names yet).

**File Renames:** | From | To | |------|-----| | `lib/zig/geometry/triangle.zig` |
`lib/zig/geometry/prism.zig` | | `lib/zig/geometry/circle.zig` | `lib/zig/geometry/boundary.zig` | |
`lib/zig/geometry/line.zig` | `lib/zig/geometry/segment.zig` | | `lib/zig/dither/ordered_dither.zig`
| `lib/zig/dither/ordered.zig` |

**Import Updates Required:**

- All files that import these modules need path updates
- `root.zig` - Update 4 import paths
- Test files - Update import paths

**Pattern to search/replace:**

- `@import("geometry/triangle.zig")` → `@import("geometry/prism.zig")`
- `@import("geometry/circle.zig")` → `@import("geometry/boundary.zig")`
- `@import("geometry/line.zig")` → `@import("geometry/segment.zig")`
- `@import("dither/ordered_dither.zig")` → `@import("dither/ordered.zig")`

**Exit Criteria:** `npm run ci` passes with new file names.

**Handover Note:** Files renamed. Types still have old names (Triangle, Circle, Segment type already
correct).

---

## Phase 6: Rename Types

**Goal:** Rename type names to match their domain purpose.

**Type Renames:** | Module | Old Type | New Type | |--------|----------|----------| |
`geometry/prism.zig` | `Triangle` | `Prism` | | `geometry/boundary.zig` | `Circle` | `Boundary` |

**Files Requiring Type Name Updates:**

For `Triangle` → `Prism`:

- `geometry/prism.zig` - Define type as `Prism`
- `geometry/intersect.zig` - Uses `triangle.Triangle`
- `rendering/band.zig` - Uses `triangle.Triangle`
- `rendering/clip.zig` - Uses `triangle.Triangle`
- `rendering/gradient.zig` - Uses `triangle.Triangle`
- `effects/grain.zig` - Uses `triangle.Triangle`
- `scene.zig` - Uses `triangle.Triangle`
- `spectrum.zig` - Uses `triangle.Triangle`
- Test files: `triangle_test.zig`, `band_test.zig`, `spectrum_test.zig`

For `Circle` → `Boundary`:

- `geometry/boundary.zig` - Define type as `Boundary`
- `geometry/intersect.zig` - Uses `circle.Circle`
- `rendering/clip.zig` - Uses `circle.Circle`
- `rendering/markers.zig` - Uses `circle.Circle`
- `scene.zig` - Uses `circle.Circle`
- `spectrum.zig` - Uses `circle.Circle`
- Test files: `spectrum_test.zig`

**Pattern to search/replace:**

- `triangle.Triangle` → `prism.Prism`
- `circle.Circle` → `boundary.Boundary`
- Variable names: `tri` → `prism`, but be careful with generic `tri` usage

**Exit Criteria:** `npm run ci` passes with new type names.

**Handover Note:** Types renamed. Still need to rename `equilateral()` → `init()` and move rendering
logic.

---

## Phase 7: Rename Constructor

**Goal:** Rename `Prism.equilateral()` to `Prism.init()`.

**Changes in `geometry/prism.zig`:**

- Rename `pub fn equilateral(...)` to `pub fn init(...)`

**Files Requiring Updates:**

- Search for `.equilateral(` across codebase
- Update all call sites to `.init(`

**Known Callers:**

- `scene.zig` - Creates the prism
- `tests/triangle_test.zig` - Test creates triangles

**Exit Criteria:** `npm run ci` passes with `init()` constructor.

**Handover Note:** Naming refactoring complete. Ready for the complex logic move in Phase 8.

---

## Phase 8: Extract Glow Rendering to glow.zig

**Goal:** Move glow rendering functions from `band.zig` to `rendering/glow.zig`.

This is the most complex phase. Currently:

- `glow.zig` has: `Falloff` enum, `Config` struct
- `band.zig` has: `renderGlowLine()`, `renderPrismGlow()` methods on `Context`

**Step 8a: Move `smoothEdgeDistance` from prism.zig to glow.zig**

In `geometry/prism.zig`, the method `smoothEdgeDistance()` is rendering-specific (for glow). Move it
to `rendering/glow.zig` as a free function:

```zig
// In rendering/glow.zig
pub fn smoothPrismDistance(prism: *const Prism, point: vec2.Vec2, k: f32) f32 {
    // Implementation from prism.smoothEdgeDistance()
}
```

**Step 8b: Extract renderGlowLine from band.zig**

Move `Context.renderGlowLine()` method to `glow.zig` as a free function:

```zig
// In rendering/glow.zig
pub fn renderLine(ctx: *band.Context, segment: segment.Segment, config: Config, ...) void {
    // Implementation from band.Context.renderGlowLine()
}
```

**Step 8c: Extract renderPrismGlow from band.zig**

Move `Context.renderPrismGlow()` method to `glow.zig` as a free function:

```zig
// In rendering/glow.zig
pub fn renderPrismEdges(ctx: *band.Context, prism: *const Prism, ...) void {
    // Implementation from band.Context.renderPrismGlow()
}
```

**Step 8d: Update callers**

Change call sites from method calls to free function calls:

- `ctx.renderGlowLine(...)` → `glow.renderLine(ctx, ...)`
- `ctx.renderPrismGlow(...)` → `glow.renderPrismEdges(ctx, ...)`

**Files to Update:**

- `scene.zig` - Add `glow` import, update call sites
- `tests/band_test.zig` - Update test calls

**Exit Criteria:** `npm run ci` passes with glow rendering in `glow.zig`.

**Handover Note:** Glow rendering extracted. Ready for gradient extraction in Phase 9.

---

## Phase 9: Extract Gradient Rendering to gradient.zig

**Goal:** Move gradient rendering from `band.zig` to `rendering/gradient.zig`.

Currently:

- `gradient.zig` has: `Config` struct, `Geometry` struct
- `band.zig` has: `renderGradient()` method on `Context`

**Step 9a: Extract renderGradient from band.zig**

Move `Context.renderGradient()` method to `gradient.zig` as a free function:

```zig
// In rendering/gradient.zig
pub fn render(ctx: *band.Context, config: Config, geometry: Geometry, cache: *const palette.Cache) void {
    // Implementation from band.Context.renderGradient()
}
```

**Step 9b: Update callers**

Change call sites:

- `ctx.renderGradient(...)` → `gradient.render(ctx, ...)`

**Files to Update:**

- `scene.zig` - Update gradient call sites

**Exit Criteria:** `npm run ci` passes with gradient rendering in `gradient.zig`.

**Handover Note:** Rendering logic extraction complete. Ready for cleanup in Phase 10.

---

## Phase 10: Cleanup & Final Verification

**Goal:** Remove dead code, verify all tests pass, update root.zig exports.

**Tasks:**

1. Remove any dead methods from `band.zig` (should now be thin canvas)
2. Verify `band.zig` only contains:
   - `Context` struct
   - `clear()`, `clearWithBackground()`
   - Primitive helpers (pixel blending)
3. Update `root.zig` to reflect new module organization
4. Run full test suite
5. Review for any remaining inconsistencies

**Exit Criteria:** `npm run ci` passes. Code matches target structure in REFACTORING.md.

**Handover Note:** Refactoring complete!

---

## Quick Reference: File Locations After Refactoring

```
lib/zig/
├── math/
│   ├── vec2.zig
│   └── range.zig
├── geometry/
│   ├── prism.zig          (was triangle.zig, type Prism)
│   ├── boundary.zig       (was circle.zig, type Boundary)
│   ├── segment.zig        (was line.zig)
│   ├── ray.zig
│   └── intersect.zig
├── rendering/
│   ├── band.zig           (thin canvas)
│   ├── glow.zig           (config + rendering)
│   ├── gradient.zig       (config + rendering)
│   ├── clip.zig
│   └── markers.zig
├── color/
│   ├── color.zig
│   ├── oklab.zig
│   ├── gamma.zig
│   └── palette.zig
├── effects/
│   ├── effect.zig
│   ├── grain.zig
│   └── vignette.zig
├── dither/
│   ├── dither.zig
│   ├── ordered.zig        (was ordered_dither.zig)
│   └── error_diffusion.zig
├── spectrum.zig
├── clock.zig
├── scene.zig
├── compat.zig
└── root.zig
```

---

## Agent Handover Protocol

When starting a new phase:

1. **Read this plan** to understand the current phase
2. **Check git status** to see what's been done
3. **Run `npm run ci`** to verify the build is green
4. **Execute the phase tasks**
5. **Run `npm run ci`** to verify the build passes
6. **Commit with message:** `Refactor: Phase N - <phase description>`

If context is getting full mid-phase:

1. Commit partial progress with clear message
2. Update the Handover Note for the current phase
3. The next agent reads this plan and continues
