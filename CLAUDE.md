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
- **SIMD**: Use `@Vector` types for calculations to leverage hardware acceleration
- **No abbreviations**: Use full names (`distance`, not `dist`)
- **No aliases**: Don't create aliases like `const FooBar = foo.Bar`. Use the qualified name
  (`foo.Bar`) directly.
- **No re-exports**: Don't re-export imports (`pub const foo = @import("foo.zig")`). Exception:
  `root.zig` may re-export for the public API.
- **No fake `pub`**: Don't mark unused code as `pub` to suppress warnings. Remove it instead.
- **Const slices**: Use `[]const T` for slice parameters that are only read from; use `[]T` only for
  output buffers that are written to.
