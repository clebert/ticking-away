#!/bin/bash

set -e

clang \
  -std=c23 \
  -Wall \
  -Wextra \
  -Werror \
  -Isrc/include \
  -lm \
  -o tests/bounce_test \
  tests/bounce_test.c

echo "Built tests/bounce_test"
