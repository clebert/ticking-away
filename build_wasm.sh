#!/bin/bash

set -e

CFLAGS="
  --target=wasm32
  -std=c23
  -O3
  -flto
  -nostdlib
  -Wall
  -Wextra
  -Werror
  -Ilib
  -mbulk-memory
  -msimd128
"

LDFLAGS="
  -Wl,--export-dynamic
  -Wl,--import-memory
  -Wl,--no-entry
  -Wl,--strip-all
  -Wl,--lto-O3
"

WASM_SOURCES="
  bin/wasm/main.c
"

LIB_SOURCES="
  lib/draw/line.c
  lib/draw/pixel.c
  lib/effects/gamma.c
  lib/effects/grain.c
  lib/effects/vignette.c
  lib/geometry/intersect.c
  lib/geometry/prism.c
  lib/geometry/segment.c
  lib/layers/background.c
  lib/layers/gradient.c
  lib/layers/markers.c
  lib/layers/prism_glow.c
  lib/layers/rays.c
  lib/pipeline.c
  lib/quantize/direct.c
  lib/quantize/dither_error.c
  lib/quantize/dither_ordered.c
  lib/quantize/dither.c
  lib/scene.c
"

echo "==> Building public/index.wasm"

clang $CFLAGS -o public/index.wasm $WASM_SOURCES $LIB_SOURCES $LDFLAGS

echo "Built: public/index.wasm ($(wc -c < public/index.wasm | xargs) bytes)"
