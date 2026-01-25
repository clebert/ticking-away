# CLAUDE.md

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Code Style

### C/C++ Null Pointers

Always use `nullptr` for null pointers. Do not use `NULL` or `0`. When encountering existing code
that uses `NULL` or `0` for null pointers, refactor it to use `nullptr`.

### Stdlib-Free Library

The `lib/` folder must remain free of standard library dependencies to support two use cases:

1. **Embedded hardware**: No dynamic memory allocations for restricted environments
2. **Pure WASM**: Compilable to WebAssembly without Emscripten or similar toolchains

Do not use `malloc`, `calloc`, `realloc`, `free`, `alloca`, variable-length arrays, stdio functions,
or other stdlib calls in library code. Only `<stddef.h>` and `<stdint.h>` (for types like `size_t`
and `uint8_t`) are permitted. All memory is managed by the caller and passed via pointers.

Stdlib usage is always permitted in `tests/`. For `bin/`, it depends on the target—the WASM build
(`bin/wasm/`) must also remain stdlib-free.

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
