#!/bin/bash

set -e

clang \
  --target=wasm32 \
  -std=c23 \
  -O3 \
  -flto \
  -nostdlib \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -mbulk-memory \
  -msimd128 \
  -Wl,--export-dynamic \
  -Wl,--import-memory \
  -Wl,--no-entry \
  -Wl,--strip-all \
  -Wl,--lto-O3 \
  -o public/index.wasm \
  bin/wasm/main.c \
  lib/draw/line.c \
  lib/draw/pixel.c \
  lib/effects/gamma.c \
  lib/effects/grain.c \
  lib/effects/vignette.c \
  lib/geometry/intersect.c \
  lib/geometry/prism.c \
  lib/geometry/segment.c \
  lib/layers/background.c \
  lib/layers/gradient.c \
  lib/layers/markers.c \
  lib/layers/prism_glow.c \
  lib/layers/rays.c \
  lib/pipeline.c \
  lib/quantize/direct.c \
  lib/quantize/dither.c \
  lib/quantize/dither_error.c \
  lib/scene.c 

echo "Built index.wasm ($(wc -c < public/index.wasm | xargs) bytes)"
