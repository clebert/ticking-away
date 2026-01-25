#!/bin/bash

set -e

CFLAGS="-std=c23 -O3 -Wall -Wextra -Werror -Ilib"
LDFLAGS="-lm"

build_test() {
  local name=$1
  shift
  clang $CFLAGS -o "tests/${name}_test" "tests/${name}_test.c" "$@" $LDFLAGS
  echo "Built: tests/${name}_test"
}

echo "==> Building tests"

# To add a new test, add a line like:
#   build_test <name> <lib sources...>

build_test gamma      lib/effects/gamma.c
build_test grain      lib/effects/grain.c
build_test dither     lib/quantize/dither.c lib/quantize/dither_error.c lib/quantize/dither_ordered.c
build_test vignette   lib/effects/vignette.c
build_test pipeline   lib/pipeline.c lib/effects/{gamma,grain,vignette}.c
build_test prism      lib/geometry/prism.c
build_test intersect  lib/geometry/{intersect,prism}.c
build_test segment    lib/geometry/segment.c
build_test pixel      lib/draw/pixel.c
build_test line       lib/draw/{line,pixel}.c lib/geometry/{segment,prism}.c
build_test background lib/layers/background.c
build_test rays       lib/layers/rays.c lib/geometry/{prism,intersect,segment}.c lib/draw/{line,pixel}.c
build_test gradient   lib/layers/gradient.c lib/geometry/prism.c
build_test prism_glow lib/layers/prism_glow.c lib/geometry/{prism,segment}.c lib/draw/pixel.c
build_test markers    lib/layers/markers.c lib/draw/{line,pixel}.c lib/geometry/{segment,prism}.c
build_test scene      lib/scene.c lib/layers/{background,rays,gradient,prism_glow,markers}.c \
                      lib/geometry/{prism,intersect,segment}.c lib/draw/{line,pixel}.c lib/effects/gamma.c
