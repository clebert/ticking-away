#!/bin/bash

set -e

clang \
  -std=c23 \
  -Wall \
  -Wextra \
  -Werror \
  -Iinclude \
  -lm \
  -o tests/bounce_test \
  tests/bounce_test.c

echo "Built tests/bounce_test"
