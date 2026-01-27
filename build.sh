#!/usr/bin/env bash

set -euo pipefail

# Build script
# Usage: ./build.sh [--skip-inky]

skip_inky=false
for arg in "$@"; do
  case $arg in
    --skip-inky)
      skip_inky=true
      ;;
  esac
done

if [ "$skip_inky" = false ]; then
  zig build inky -Doptimize=ReleaseFast
fi

zig build wasm
zig build zig-wasm

echo "==> Vite production build"
npx vite build

echo "==> Build complete"
