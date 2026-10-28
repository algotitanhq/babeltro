#!/bin/sh
# Builds the Zig port as a WebAssembly module for the lab.
#
# --release=fast is ReleaseFast: no safety checks in the hot loops. The code
# clamps before every float-to-int conversion, as Go does, so nothing relies
# on them. Extra arguments go to `zig build`: -Doptimize=safe keeps every
# check (it wins over --release), -Dlang=GO renames the finale's language.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
zig=${ZIG:-zig}
command -v "$zig" >/dev/null || zig=/opt/homebrew/bin/zig
mkdir -p "$root/web/public/wasm"
cd "$root/ports/zig"
"$zig" build --release=fast "$@"
cp zig-out/bin/babeltro.wasm "$root/web/public/wasm/zig.wasm"
