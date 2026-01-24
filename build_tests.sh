#!/bin/bash

set -e

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/gamma_test \
  tests/gamma_test.c \
  lib/kernels/gamma.c \
  -lm

echo "Built tests/gamma_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/grain_test \
  tests/grain_test.c \
  lib/kernels/grain.c

echo "Built tests/grain_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/dither_test \
  tests/dither_test.c \
  lib/kernels/dither.c \
  -lm

echo "Built tests/dither_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/vignette_test \
  tests/vignette_test.c \
  lib/kernels/vignette.c \
  -lm

echo "Built tests/vignette_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/pipeline_test \
  tests/pipeline_test.c \
  lib/pipeline.c \
  lib/kernels/gamma.c \
  lib/kernels/grain.c \
  lib/kernels/vignette.c \
  -lm

echo "Built tests/pipeline_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/prism_test \
  tests/prism_test.c \
  lib/geometry/prism.c \
  -lm

echo "Built tests/prism_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/intersect_test \
  tests/intersect_test.c \
  lib/geometry/intersect.c \
  lib/geometry/prism.c \
  -lm

echo "Built tests/intersect_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/segment_test \
  tests/segment_test.c \
  lib/geometry/segment.c \
  -lm

echo "Built tests/segment_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/pixel_test \
  tests/pixel_test.c \
  lib/draw/pixel.c

echo "Built tests/pixel_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/line_test \
  tests/line_test.c \
  lib/draw/line.c \
  lib/draw/pixel.c \
  lib/geometry/segment.c \
  lib/geometry/prism.c \
  -lm

echo "Built tests/line_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/background_test \
  tests/background_test.c \
  lib/layers/background.c

echo "Built tests/background_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/rays_test \
  tests/rays_test.c \
  lib/layers/rays.c \
  lib/geometry/prism.c \
  lib/geometry/intersect.c \
  lib/geometry/segment.c \
  lib/draw/line.c \
  lib/draw/pixel.c \
  -lm

echo "Built tests/rays_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/gradient_test \
  tests/gradient_test.c \
  lib/layers/gradient.c \
  lib/geometry/prism.c \
  -lm

echo "Built tests/gradient_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/prism_glow_test \
  tests/prism_glow_test.c \
  lib/layers/prism_glow.c \
  lib/geometry/prism.c \
  lib/geometry/segment.c \
  lib/draw/pixel.c \
  -lm

echo "Built tests/prism_glow_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/markers_test \
  tests/markers_test.c \
  lib/layers/markers.c \
  lib/draw/line.c \
  lib/draw/pixel.c \
  lib/geometry/segment.c \
  lib/geometry/prism.c \
  -lm

echo "Built tests/markers_test"

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Ilib \
  -o tests/scene_test \
  tests/scene_test.c \
  lib/scene.c \
  lib/layers/background.c \
  lib/layers/rays.c \
  lib/layers/gradient.c \
  lib/layers/prism_glow.c \
  lib/layers/markers.c \
  lib/geometry/prism.c \
  lib/geometry/intersect.c \
  lib/geometry/segment.c \
  lib/draw/line.c \
  lib/draw/pixel.c \
  lib/kernels/gamma.c \
  -lm

echo "Built tests/scene_test"
