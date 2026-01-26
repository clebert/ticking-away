#!/usr/bin/env bash

set -euo pipefail

# Test runner script
# Usage: ./test.sh

zig build test

echo "==> All tests passed"
