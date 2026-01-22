#!/bin/bash

set -e

clang \
  --target=wasm32 \
  -std=c23 \
  -O3 \
  -nostdlib \
  -Wall \
  -Wextra \
  -Werror \
  -Iinclude \
  -mbulk-memory \
  -msimd128 \
  -Wl,--export-dynamic \
  -Wl,--import-memory \
  -Wl,--no-entry \
  -Wl,--strip-all \
  -o public/index.wasm \
  src/wasm.c

echo "Built index.wasm ($(wc -c < public/index.wasm | xargs) bytes)"
