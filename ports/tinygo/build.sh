#!/bin/sh
# Builds the Go reference itself — the same go/ sources, byte for byte —
# with TinyGo instead of the official Go compiler. TinyGo goes through LLVM,
# like clang and rustc; Go has its own wasm backend. The difference between
# the two modules is the difference between the compilers, not the language.
#
# -opt=2: optimise for speed. -scheduler=asyncify is TinyGo's default on
# wasip1; the effects never block, so it costs nothing here.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
tinygo=${TINYGO:-tinygo}
command -v "$tinygo" >/dev/null || tinygo=/opt/homebrew/bin/tinygo
mkdir -p "$root/web/public/wasm"
cd "$root/go"
"$tinygo" build -target=wasip1 -buildmode=c-shared -opt=2 -no-debug \
  -o "$root/web/public/wasm/tinygo.wasm" ./cmd/wasm
