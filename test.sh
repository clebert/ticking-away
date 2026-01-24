#!/usr/bin/env bash

set -euo pipefail

# Test runner script
# Usage: ./test.sh

./build_tests.sh
echo
echo "==> Running tests"
echo
./tests/gamma_test
echo
./tests/grain_test
echo
./tests/dither_test
echo
./tests/vignette_test
echo
./tests/pipeline_test
echo
./tests/prism_test
echo
./tests/intersect_test
echo
./tests/segment_test
echo
./tests/pixel_test
echo
./tests/line_test
echo
./tests/background_test
echo
./tests/rays_test
echo
./tests/gradient_test
echo
./tests/prism_glow_test
echo
./tests/markers_test
echo
./tests/scene_test
echo
echo "==> All tests passed"
