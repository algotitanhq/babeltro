#!/bin/sh
# Builds the x86 assembly port: NASM assembles ports/x86/main.asm (and the
# files it includes) into a flat binary image, which is embedded as a C
# array in cpu.c, the x86 interpreter, compiled to wasm like the C port.
#
# -ffp-contract=off: the interpreter's own float maths must round once per
# SSE instruction, never fuse a*b+c.
set -eu
# X86_LANG=C OUT=... builds a variant whose finale spells another name: the
# proof that the name is the only difference from the C finale.
root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/ports/x86"
llvm=${LLVM:-/opt/homebrew/opt/llvm}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$root/web/public/wasm"
(cd "$here" && nasm -f bin -w+all -w-reloc-abs-dword ${X86_LANG:+"-DLANG='$X86_LANG'"} -o "$tmp/fx.bin" main.asm)
(cd "$tmp" && xxd -i fx.bin > fx_bin.h)
"$llvm/bin/clang" --target=wasm32-wasip1 \
  --sysroot=/opt/homebrew/opt/wasi-libc/share/wasi-sysroot \
  -resource-dir=/opt/homebrew/opt/wasi-runtimes/share/wasi-runtimes \
  -std=c17 -O2 -ffp-contract=off -Wall -Wextra \
  -mexec-model=reactor -I "$tmp" \
  -o "${OUT:-$root/web/public/wasm/x86.wasm}" "$here/cpu.c"
