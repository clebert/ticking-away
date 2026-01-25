#!/bin/bash

set -e

CFLAGS="-std=c23 -O2 -Wall -Wextra -Werror -Ilib"
LDFLAGS="-lm"

INKY_SOURCES="
  bin/inky/display.c
  bin/inky/gpio.c
  bin/inky/main.c
  bin/inky/pack.c
  bin/inky/spi.c
"

LIB_SOURCES="
  lib/draw/line.c
  lib/draw/pixel.c
  lib/effects/gamma.c
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
  lib/quantize/dither.c
  lib/scene.c
"

echo "==> Building bin/inky/watchface"

clang $CFLAGS -o bin/inky/watchface $INKY_SOURCES $LIB_SOURCES $LDFLAGS

echo "Built: bin/inky/watchface"
