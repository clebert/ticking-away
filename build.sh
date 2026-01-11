#!/bin/bash

set -e

# Common flags
COMMON_FLAGS="--target=wasm32 -std=c23 -O3 -flto -nostdlib -Wall -Wextra -Werror -Wl,--no-entry -Wl,--export-dynamic -Wl,--import-memory -Wl,--strip-all"

# Build index.wasm
clang \
  $COMMON_FLAGS \
  -msimd128 \
  -mbulk-memory \
  -o public/index.wasm \
  src/wasm.c

echo "Built index.wasm ($(wc -c < public/index.wasm | xargs) bytes)"
