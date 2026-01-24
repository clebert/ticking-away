#!/usr/bin/env bash

set -euo pipefail

# Build script
# Usage: ./build.sh

./build_wasm.sh

echo "==> Vite production build"
npx vite build

echo "==> Build complete"
