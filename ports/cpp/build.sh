#!/bin/sh
# Builds the C++ port as a WebAssembly reactor for the lab.
#
# -ffp-contract=off: never fuse a*b+c into one rounding, or the pixels drift
# from the reference. -mexec-model=reactor: no main; _initialize runs the
# static initialisers (the sine tables), then the host calls the exports.
# -fno-exceptions -fno-rtti: neither is used, and both cost module size.
#
# The wasi-runtimes sysroot carries libc++ and libc++abi only, so the C
# library (headers, crt1-reactor.o, libc.a) comes from the wasi-libc sysroot
# and libc++ is added on top of it.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/ports/cpp"
llvm=${LLVM:-/opt/homebrew/opt/llvm}
libc=${WASI_LIBC:-/opt/homebrew/opt/wasi-libc/share/wasi-sysroot}
rt=${WASI_RUNTIMES:-/opt/homebrew/opt/wasi-runtimes/share}
mkdir -p "$root/web/public/wasm"
"$llvm/bin/clang++" --target=wasm32-wasip1 \
  --sysroot="$libc" \
  -nostdinc++ -isystem "$rt/wasi-sysroot/include/wasm32-wasip1/c++/v1" \
  -L"$rt/wasi-sysroot/lib/wasm32-wasip1" \
  -resource-dir="$rt/wasi-runtimes" \
  -std=c++23 -O2 -ffp-contract=off -fno-exceptions -fno-rtti \
  -Wall -Wextra -Wpedantic \
  -mexec-model=reactor \
  -o "$root/web/public/wasm/cpp.wasm" "$here"/*.cpp
