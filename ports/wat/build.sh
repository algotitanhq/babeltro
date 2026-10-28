#!/bin/sh
# Builds the hand-written WebAssembly port: no compiler, just the assembler.
#
# Each .wat file here is a list of module fields; this script wraps them, in
# a fixed order, in one (module ...) and hands it to wat2wasm. Only two
# post-MVP features are switched on, the two the code uses: multi-value
# (functions returning several results) and bulk memory (memory.fill and
# memory.copy). Everything else wabt enables by default is turned off, so a
# stray SIMD or saturating-truncation instruction is an assembly error.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/ports/wat"
wat2wasm=${WAT2WASM:-/opt/homebrew/bin/wat2wasm}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{
  echo '(module'
  for f in memory fmath palette font text starfield tunnel plasma rotozoom metaballs \
           grid fire mandelbrot finale main; do
    cat "$here/$f.wat"
  done
  echo ')'
} > "$tmp/babeltro.wat"
mkdir -p "$root/web/public/wasm"
"$wat2wasm" \
  --disable-exceptions --disable-mutable-globals --disable-saturating-float-to-int \
  --disable-sign-extension --disable-simd --disable-tail-call --disable-reference-types \
  --disable-annotations --disable-memory64 --disable-multi-memory \
  --disable-extended-const --disable-relaxed-simd \
  -o "$root/web/public/wasm/wat.wasm" "$tmp/babeltro.wat"
