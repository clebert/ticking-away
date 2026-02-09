# CLAUDE.md

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Commands

After code changes, always run:

```bash
npm run ci
```

### Available Scripts

| Script             | Description                                 |
| ------------------ | ------------------------------------------- |
| `npm run build`    | Build WASM module and Vite production build |
| `npm run ci`       | Run full CI pipeline (build, lint, test)    |
| `npm run lint`     | Run linters                                 |
| `npm run lint:fix` | Run linters with auto-fix                   |
| `npm test`         | Run tests                                   |

### Profiling

Build and run the native profiling binary for use with valgrind/callgrind:

```bash
zig build profile -Doptimize=ReleaseFast
zig-out/bin/profile [iteration_count]
```

## Zig Code Style

Follow the [Zig style guide](https://ziglang.org/documentation/0.15.2/#Style-Guide):

- **Types**: `PascalCase`, acronyms as single words (`Rgb`, not `RGB`)
- **File names**: `PascalCase.zig` for struct modules (file IS a struct via `@This()`),
  `snake_case.zig` for namespace modules (only functions/constants, no struct fields)
- **Functions**: `camelCase`
- **Variables**: `snake_case`
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
