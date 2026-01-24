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

echo "==> clang-format (C)"
C_FILES=$(find lib bin tests -name '*.c' -o -name '*.h')
if $FIX; then
    echo "$C_FILES" | xargs clang-format -i
else
    echo "$C_FILES" | xargs clang-format --dry-run --Werror
fi

echo "==> cppcheck (C)"
# Define nullptr for cppcheck since it only supports up to C11
cppcheck --enable=warning,style,performance,portability \
    -D 'nullptr=((void*)0)' \
    --suppressions-list=.cppcheck-suppressions \
    --error-exitcode=1 --quiet lib/ bin/ tests/

echo "==> clang-tidy (C)"
tidy_output=$(find lib bin tests -name '*.c' | xargs -I {} clang-tidy {} -- -std=c23 -I lib 2>&1 \
    | grep -Ev "^[0-9]+ warnings generated\.$|^Suppressed [0-9]+ warnings|^Use -header-filter|^Use -system-headers" \
    || true)
if [ -n "$tidy_output" ]; then
    echo "$tidy_output"
    exit 1
fi

echo "==> include-what-you-use (C)"
iwyu_output=$(find lib bin tests -name '*.c' -o -name '*.h' | xargs -I {} iwyu -std=c2x -I lib {} 2>&1 \
    | grep -Ev "has correct #includes/fwd-decls\)|^$" \
    || true)
if [ -n "$iwyu_output" ]; then
    echo "$iwyu_output"
    exit 1
fi

echo "==> All checks passed"
