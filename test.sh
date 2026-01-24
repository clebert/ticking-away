#!/usr/bin/env bash

set -euo pipefail

# Test runner script
# Usage: ./test.sh

./build_tests.sh

echo "==> Running tests"

./tests/gamma_test
./tests/grain_test
./tests/dither_test
./tests/vignette_test
./tests/pipeline_test
./tests/prism_test
./tests/intersect_test
./tests/segment_test
./tests/pixel_test
./tests/line_test
./tests/background_test
./tests/rays_test
./tests/gradient_test
./tests/prism_glow_test
./tests/markers_test
./tests/scene_test

echo "==> All tests passed"
