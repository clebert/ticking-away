#!/usr/bin/env bash

set -euo pipefail

# Linting and formatting script
# Usage: ./lint.sh [--fix]

FIX=false

for arg in "$@"; do
    case $arg in
        --fix) FIX=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

echo "==> TypeScript"
npx tsc

echo "==> Biome (TypeScript/JavaScript)"
if $FIX; then
    npx biome check --write --unsafe
else
    npx biome check
fi

echo "==> Prettier (HTML/Markdown/YAML)"
if $FIX; then
    npx prettier --write "**/*.{html,md,yaml,yml}"
else
    npx prettier --check "**/*.{html,md,yaml,yml}"
fi

echo "==> Zig"
zig fmt --check build.zig || {
    if $FIX; then
        zig fmt build.zig
    else
        exit 1
    fi
}

echo "==> All checks passed"
