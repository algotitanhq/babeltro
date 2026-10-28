#!/bin/sh
# Builds the C port as a WebAssembly reactor for the lab.
#
# -ffp-contract=off: never fuse a*b+c into one rounding, or the pixels drift
# from the reference. -mexec-model=reactor: no main, the host calls exports.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
llvm=${LLVM:-/opt/homebrew/opt/llvm}
mkdir -p "$root/web/public/wasm"
"$llvm/bin/clang" --target=wasm32-wasip1 \
  --sysroot=/opt/homebrew/opt/wasi-libc/share/wasi-sysroot \
  -resource-dir=/opt/homebrew/opt/wasi-runtimes/share/wasi-runtimes \
  -std=c17 -O2 -ffp-contract=off -Wall -Wextra -Wpedantic \
  -mexec-model=reactor \
  -o "$root/web/public/wasm/c.wasm" "$root"/c/*.c -lm
