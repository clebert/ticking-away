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

### Finding the Zig Binary

Zig is not installed system-wide; the `ziglang.vscode-zig` VSCode extension provides version
`0.16.0` under `~/Library/Application Support/Code/User/globalStorage/ziglang.vscode-zig/zig`
(macOS). Quote the path when invoking it — it contains spaces.

## Git

Commit to `main` directly — do not create a new branch for a commit unless I explicitly ask for one.

## Zig Code Style

Follow the [Zig style guide](https://ziglang.org/documentation/0.16.0/#Style-Guide):

- **Types**: `PascalCase`, acronyms as single words (`Rgb`, not `RGB`)
- **File names**: `PascalCase.zig` for struct modules (file is a struct via `@This()`),
  `snake_case.zig` for namespace modules (functions/constants only, no struct fields)
- **Functions**: `camelCase`
- **Variables**: `snake_case`
- **Comments**: default to none — write one only when code, signature, and names can't carry the
  meaning, then in the fewest words that add a fact they don't. Worth it: a math/algorithm
  derivation, a cited magic constant (its canonical source URL allowed only here), a gotcha that
  breaks silently if violated, a non-obvious rationale, or a contract the signature can't state
  (ownership, sizing, pre/postconditions). Not worth it: restating the next line (test assertions,
  name-echoing doc-comments), generic links, prose padded around one fact, or pointers to docs,
  tickets, or conversations — though another source file is fine.
  - **Present-only**: say what the code is and why it must be so now — never its past. No removed
    code, prior versions, provenance, rejected alternatives, decision history, or future/deferred
    plans (`replaces`, `previously`, `for now`, `TODO`); such notes get read back later as
    requirements and drive changes nobody asked for. Comparing two things both present is fine.
  - **On edit**: re-read adjacent comments and delete or rewrite any that no longer fit the present.
- **SIMD**: `@Vector` types for hardware-accelerated calculations
- **No abbreviations**: full names (`distance`, not `dist`)
- **No aliases**: use the qualified name (`foo.Bar`) directly, never `const FooBar = foo.Bar`
- **No re-exports**: don't re-export imports (`pub const foo = @import("foo.zig")`); only `root.zig`
  may, for the public API
- **No fake `pub`**: don't mark unused code `pub` to silence warnings — remove it, along with any
  tests that exist only to exercise it; a symbol consumed elsewhere (including tests in _other_
  modules, e.g. `Srgb.white`) is real API, so keep it and its symmetric constants
- **Const slices**: `[]const T` for read-only slice parameters, `[]T` only for output buffers
- **Optional captures**: never accept a shadow-forced capture name (`if (grain) |g|`) — if the value
  is cheap, build it unconditionally and guard its _use_ with a boolean
  (`const grain = ...; if (enabled) grain.apply(...)`), otherwise name the optional `maybe_foo` so
  the capture stays clean (`if (maybe_grain) |grain|`)
