# CLAUDE.md

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Code Style

### C/C++ Null Pointers

Always use `nullptr` for null pointers. Do not use `NULL` or `0`. When encountering existing code
that uses `NULL` or `0` for null pointers, refactor it to use `nullptr`.

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
