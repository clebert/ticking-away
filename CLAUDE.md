# CLAUDE.md

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Architecture

The project uses a pure software renderer via WASM:

- C code in [watchface.h](src/include/watchface.h) writes directly to an RGBA framebuffer
- TypeScript reads this buffer and uses `putImageData()` to display on an HTML5 Canvas
- All rendering is per-pixel: additive blending for light rays, alpha blending for overlays

## Commands

After code changes, always run:

```bash
npm run ci          # build + check + compile + format
```

Individual tasks:

```bash
npm run build       # Vite production build
npm run check       # Biome linter
npm run check:fix   # Biome linter with auto-fix
npm run compile     # TypeScript compilation
npm run format      # Prettier check (md, yaml)
npm run format:fix  # Prettier with auto-fix
npm run start       # Vite dev server
npm test            # Run C test harness
```

## TypeScript

Uses `exactOptionalPropertyTypes` — optional properties need `?: T | undefined`.
