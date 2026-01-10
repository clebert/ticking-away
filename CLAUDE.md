# CLAUDE.md

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

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
```

## TypeScript

Uses `exactOptionalPropertyTypes` — optional properties need `?: T | undefined`.
