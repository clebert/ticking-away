# CLAUDE.md

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Commands

After code changes, always run:

```bash
npm run ci
```

### Available Scripts

| Script             | Command                                     | Description                                 |
| ------------------ | ------------------------------------------- | ------------------------------------------- |
| `npm run build`    | `./build.sh`                                | Build WASM module and Vite production build |
| `npm run ci`       | `npm run build && npm run lint && npm test` | Run full CI pipeline (build, lint, test)    |
| `npm run lint`     | `./lint.sh`                                 | Run linters                                 |
| `npm run lint:fix` | `./lint.sh --fix`                           | Run linters with auto-fix                   |
| `npm test`         | `./test.sh`                                 | Run tests                                   |

## Zig Code Style

Follow the [Zig style guide](https://ziglang.org/documentation/0.15.2/#Style-Guide):

- **Types**: `PascalCase`, acronyms as single words (`Rgb`, not `RGB`)
- **Functions/variables**: `camelCase`
- **Comments**: Only for math formulas or non-obvious algorithms; avoid trivial comments
- **Avoid redundancy**: Names should be clear without repeating context from the namespace
- **SIMD**: Use `@Vector` types for calculations to leverage hardware acceleration
- **Proper types**: Use `bool` for booleans, not integers; use appropriate numeric types
- **Separation of concerns**: Keep modules focused on a single responsibility
- **No abbreviations**: Use full names (`distance`, not `dist`); only abbreviate when commonly
  accepted (`ctx`)
- **Module-as-namespace imports**: Import modules as `const color = @import("color.zig")`, then
  access types as `color.Color`. Don't import types directly.
- **No aliases**: Don't create aliases like `const MarkerConfig = markers.Config`. Use the qualified
  name (`markers.Config`) directly.
- **No re-exports**: Don't re-export imports (`pub const ordered = @import("ordered.zig")`).
  Exception: `root.zig` may re-export for the public API.
- **No fake `pub`**: Don't mark unused code as `pub` to suppress warnings. Remove it instead.
- **No module.Type naming**: Don't name a type the same as its file (e.g., `palette.Palette`). This
  conflicts when importing the module with the same name as a variable.
