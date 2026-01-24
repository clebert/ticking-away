#!/bin/bash

set -e

CFLAGS="-std=c23 -O3 -Wall -Wextra -Werror -Ilib"

build_test() {
  local name=$1
  shift
  clang $CFLAGS -o "tests/${name}_test" "tests/${name}_test.c" "$@"
  echo "Built tests/${name}_test"
}

# To add a new test, add a line like:
#   build_test <name> <lib sources...> [-lm if needed]

build_test gamma      lib/kernels/gamma.c -lm
build_test grain      lib/kernels/grain.c
build_test dither     lib/kernels/dither.c -lm
build_test vignette   lib/kernels/vignette.c -lm
build_test pipeline   lib/pipeline.c lib/kernels/{gamma,grain,vignette}.c -lm
build_test prism      lib/geometry/prism.c -lm
build_test intersect  lib/geometry/{intersect,prism}.c -lm
build_test segment    lib/geometry/segment.c -lm
build_test pixel      lib/draw/pixel.c
build_test line       lib/draw/{line,pixel}.c lib/geometry/{segment,prism}.c -lm
build_test background lib/layers/background.c
build_test rays       lib/layers/rays.c lib/geometry/{prism,intersect,segment}.c lib/draw/{line,pixel}.c -lm
build_test gradient   lib/layers/gradient.c lib/geometry/prism.c -lm
build_test prism_glow lib/layers/prism_glow.c lib/geometry/{prism,segment}.c lib/draw/pixel.c -lm
build_test markers    lib/layers/markers.c lib/draw/{line,pixel}.c lib/geometry/{segment,prism}.c -lm
build_test scene      lib/scene.c lib/layers/{background,rays,gradient,prism_glow,markers}.c \
                      lib/geometry/{prism,intersect,segment}.c lib/draw/{line,pixel}.c lib/kernels/gamma.c -lm
