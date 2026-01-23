#!/bin/bash

set -e

clang \
  -std=c23 \
  -O3 \
  -Wall \
  -Wextra \
  -Werror \
  -Iinclude \
  -o tools/export_png \
  tools/export_png.c \
  -lm

echo "Built tools/export_png"
