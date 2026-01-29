# Zig Codebase Refactoring Plan

This document captures the rationale and decisions for reorganizing the Zig codebase.

## Problem Statement

The current codebase has organizational inconsistencies that make it harder to navigate and extend:

1. **Generic names for specialized things** - `Triangle` is only ever used as the prism, `Circle` is
   only ever the watch boundary, yet they have generic names suggesting reusability that doesn't
   exist.

2. **Mixed concerns within modules** - `triangle.zig` contains both pure geometry methods
   (`containsPoint`, `scanlineRange`) and rendering-specific methods (`smoothEdgeDistance` for glow
   calculations).

3. **Incomplete modules** - `glow.zig` has `Falloff` and `Config` but the actual glow rendering
   logic lives in `band.zig`. To understand "how glow works", you must look in multiple places.

4. **Flat structure with no organizing principle** - All 20+ files live in `lib/zig/` with no folder
   structure. There's no system guiding where new code should go.

5. **Redundant naming** - The `equilateral()` constructor on a type that is always equilateral.

## Design Principles

### Principle 1: Name Types for What They ARE

If something exists for one purpose in this codebase, name it for that purpose.

| Current         | New        | Rationale                      |
| --------------- | ---------- | ------------------------------ |
| `Triangle`      | `Prism`    | It's always the prism          |
| `Circle`        | `Boundary` | It's always the watch boundary |
| `equilateral()` | `init()`   | Prism is always equilateral    |

### Principle 2: Organize by Concept, Not Abstraction Level

Group code by what concept it implements, not by how "generic" it seems.

| Folder       | Contains                      | Test Question                               |
| ------------ | ----------------------------- | ------------------------------------------- |
| `math/`      | Pure math primitives          | "Is this math with no spatial meaning?"     |
| `geometry/`  | Shapes and spatial operations | "Is this about shapes or space?"            |
| `rendering/` | Visual output                 | "Is this about how things look on screen?"  |
| `color/`     | Color math                    | "Is this about color values?"               |
| `effects/`   | Post-processing               | "Is this a filter applied after rendering?" |
| `dither/`    | Dithering algorithms          | "Is this about quantization/dithering?"     |
| Top-level    | Domain orchestration          | "Does this coordinate multiple concepts?"   |

### Principle 3: Modules Own Their Concepts Completely

If a module is named `glow`, ALL glow-related code lives there - data types, calculations, and
rendering. No splitting behavior across files.

**Before:**

```
glow.zig      → Falloff, Config (just data)
band.zig      → renderGlowLine(), renderPrismGlow() (behavior)
triangle.zig  → smoothEdgeDistance() (calculation)
```

**After:**

```
glow.zig      → Falloff, Config, smoothPrismDistance(), renderLine(), renderPrismEdges()
```

### Principle 4: Thin Canvas, Module Painters

The render context (`band.Context`) should be a thin canvas that holds pixels and provides primitive
operations. Each rendering module knows how to paint itself onto the canvas.

**Canvas responsibilities:**

- Buffer management (allocation, clearing)
- Coordinate system (dimensions, band offset)
- Primitive operations (blend pixel, scanline iteration)

**Module responsibilities:**

- Each module renders its own concept: `glow.renderLine(ctx, ...)`, `gradient.render(ctx, ...)`

### Principle 5: Methods vs Free Functions

| Use Method When...                   | Use Free Function When...         |
| ------------------------------------ | --------------------------------- |
| Operation is intrinsic to the type   | Operation combines multiple types |
| Would exist in ANY use of this shape | Specific to our rendering/domain  |
| Accesses internal state              | Only uses public interface        |

**Examples:**

- `prism.containsPoint()` → method (intrinsic geometry)
- `glow.smoothPrismDistance(prism, point, k)` → free function (rendering-specific)

## Target Structure

```
lib/zig/
├── math/                  # Pure math primitives
│   ├── vec2.zig           # Vec2 type, dot, length, normalize
│   └── range.zig          # Range (x_min, x_max)
│
├── geometry/              # Shapes and spatial operations
│   ├── segment.zig        # Line segment (distance calculations)
│   ├── ray.zig            # Ray (origin + direction)
│   ├── prism.zig          # Equilateral triangle (the prism)
│   ├── boundary.zig       # Circle (the watch boundary)
│   └── intersect.zig      # Ray-shape intersections
│
├── rendering/             # Visual output
│   ├── band.zig           # RenderContext (thin canvas)
│   ├── glow.zig           # Glow effects (config + rendering)
│   ├── gradient.zig       # Gradient fills (config + rendering)
│   ├── clip.zig           # Clipping regions
│   └── markers.zig        # Hour markers (config + rendering)
│
├── color/                 # Color math
│   ├── color.zig          # Color type (RGBA linear)
│   ├── oklab.zig          # OkLab color space
│   ├── gamma.zig          # Gamma correction
│   └── palette.zig        # Spectral palettes
│
├── effects/               # Post-processing
│   ├── effect.zig         # Effect pipeline
│   ├── grain.zig          # Film grain
│   └── vignette.zig       # Vignette
│
├── dither/                # Dithering
│   ├── dither.zig         # Dither manager
│   ├── ordered.zig        # Bayer/ordered dithering
│   └── error_diffusion.zig
│
├── spectrum.zig           # Light path computation
├── clock.zig              # Time → angle conversion
├── scene.zig              # Main watchface composition
├── compat.zig             # C bridge
└── root.zig               # Public API
```

## Detailed Changes

### 1. Rename `triangle.zig` → `geometry/prism.zig`

**Type renames:**

- `Triangle` → `Prism`

**Method changes:**

- `equilateral(center, base_width)` → `init(center, base_width)`
- Remove `smoothEdgeDistance()` (moves to `rendering/glow.zig`)

**Keep as methods** (intrinsic geometry):

- `containsPoint()`
- `scanlineRange()`
- `getVertex()`, `getEdge()`
- `centroid()`
- `minY()`, `maxY()`

### 2. Rename `circle.zig` → `geometry/boundary.zig`

**Type renames:**

- `Circle` → `Boundary`

**Method changes:**

- Keep all methods (they're intrinsic)

### 3. Move `line.zig` → `geometry/segment.zig`

Line segments are spatial (they have position in space), so they belong in `geometry/`. Rename to
match the type name (`Segment`).

### 4. Expand `rendering/glow.zig`

**Add from `triangle.zig`:**

```zig
/// Compute smooth minimum distance from point to prism edges.
/// Used for glow rendering around the prism.
pub fn smoothPrismDistance(prism: *const Prism, point: vec2.Vec2, k: f32) f32
```

**Add from `band.zig`:**

```zig
/// Render a glowing line segment onto the canvas.
pub fn renderLine(ctx: *band.RenderContext, segment: Segment, config: Config, ...) void

/// Render glow around all prism edges.
pub fn renderPrismEdges(ctx: *band.RenderContext, prism: *const Prism, ...) void
```

### 5. Expand `rendering/gradient.zig`

**Add from `band.zig`:**

```zig
/// Render angular gradient onto the canvas.
pub fn render(ctx: *band.RenderContext, config: Config, geometry: Geometry, cache: *const palette.Cache) void
```

### 6. Slim down `rendering/band.zig`

**Remove** (moved to respective modules):

- `renderGlowLine()` → `glow.renderLine()`
- `renderPrismGlow()` → `glow.renderPrismEdges()`
- `renderGradient()` → `gradient.render()`

**Keep:**

- `RenderContext` struct (buffer, dimensions, band offset)
- `clear()`, `clearWithBackground()`
- Primitive helpers if needed (pixel blending, scanline utilities)

### 7. Move `markers.zig` → `rendering/markers.zig`

Markers are a rendering concept. The module already has both config and rendering logic, which is
correct. Just move to the rendering folder.

### 8. Rename `ordered_dither.zig` → `dither/ordered.zig`

Shorter name, matches the pattern of other files. The type inside is already clear about what it
does.

### 9. Create folder structure

Move files into folders (using current names, renames happen in later steps):

- `vec2.zig`, `range.zig` → `math/`
- `ray.zig`, `intersect.zig`, `triangle.zig`, `circle.zig`, `line.zig` → `geometry/`
- `band.zig`, `glow.zig`, `gradient.zig`, `clip.zig`, `markers.zig` → `rendering/`
- `color.zig`, `oklab.zig`, `gamma.zig`, `palette.zig` → `color/`
- `effect.zig`, `grain.zig`, `vignette.zig` → `effects/`
- `dither.zig`, `ordered_dither.zig`, `error_diffusion.zig` → `dither/`

After type/file renames (steps 3-4), final names will be:

- `geometry/triangle.zig` → `geometry/prism.zig`
- `geometry/circle.zig` → `geometry/boundary.zig`
- `geometry/line.zig` → `geometry/segment.zig`
- `dither/ordered_dither.zig` → `dither/ordered.zig`

### 10. Update `root.zig`

Update all imports to reflect new paths:

```zig
pub const math = struct {
    pub const vec2 = @import("math/vec2.zig");
    pub const range = @import("math/range.zig");
};

pub const geometry = struct {
    pub const prism = @import("geometry/prism.zig");
    pub const boundary = @import("geometry/boundary.zig");
    // ...
};

// ... etc
```

### 11. Update `scene.zig` calling pattern

After making `band.zig` thin, rendering calls change from methods to free functions:

**Before:**

```zig
ctx.renderGlowLine(segment, config, ...);
ctx.renderPrismGlow(prism, ...);
ctx.renderGradient(config, ...);
```

**After:**

```zig
glow.renderLine(ctx, segment, config, ...);
glow.renderPrismEdges(ctx, prism, ...);
gradient.render(ctx, config, ...);
```

This requires `scene.zig` to import `glow` and `gradient` modules directly.

### 12. Update all import statements

Every file that imports renamed/moved modules needs updating:

- `@import("triangle.zig")` → `@import("geometry/prism.zig")`
- `triangle.Triangle` → `prism.Prism`
- `Triangle.equilateral(...)` → `Prism.init(...)`
- etc.

## Migration Order

To keep the build passing throughout:

1. **Create folders** - `math/`, `geometry/`, `rendering/`, `color/`, `effects/`, `dither/`

2. **Move files without renaming** - Move files to new folders, update imports. Build should pass.

3. **Rename files** - `triangle.zig` → `prism.zig`, `circle.zig` → `boundary.zig`, `line.zig` →
   `segment.zig`, `ordered_dither.zig` → `ordered.zig`. Update imports.

4. **Rename types** - `Triangle` → `Prism`, `Circle` → `Boundary`, update all references.

5. **Rename methods** - `equilateral()` → `init()`

6. **Move rendering logic** - Extract from `band.zig` to `glow.zig`, `gradient.zig`. Update
   `scene.zig` to call free functions instead of methods. This is the most complex step.

7. **Clean up** - Remove any dead code, update comments/docs.

Run `npm run ci` after each step to verify nothing breaks.

## Test Updates

Any test files that reference renamed types or moved modules will need updating:

- References to `Triangle` → `Prism`
- References to `Circle` → `Boundary`
- Import paths for moved modules

## Open Questions

1. **Should `spectrum.zig` and `clock.zig` stay top-level or move to a folder?** They're domain
   orchestration (light paths, time conversion) that use geometry but aren't geometry themselves.
   Current decision: keep top-level alongside `scene.zig` since they're all "scene composition"
   level code.

2. **Should `RenderContext` be renamed?** Options: `RenderContext`, `Canvas`, `Context`. Current
   decision: `RenderContext` to be explicit.

3. **Should `band.zig` be renamed to `canvas.zig`?** "Band" describes the horizontal-slice rendering
   technique. "Canvas" is more intuitive. Current decision: keep `band.zig` but rename the type to
   `RenderContext`.

4. **Is the `math/` folder necessary?** `Vec2` and `Range` are arguably spatial. We could merge them
   into `geometry/`. Counter-argument: `Vec2` is used everywhere and keeping it in a minimal `math/`
   folder emphasizes it as a foundational primitive. Current decision: keep `math/` for `vec2` and
   `range`.
