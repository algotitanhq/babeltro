#!/bin/sh
# Builds the AssemblyScript port as a WebAssembly module for the lab.
#
# --runtime minimal: TLSF allocation and a mark-and-sweep collector that runs
#   only when the module calls __collect(), which bb_start does between scenes.
#   stub (bump allocation, no free) would leak every scene's tables, since
#   each bb_start builds a fresh effect as Go does; incremental would add
#   write barriers and allocation-time GC steps for no benefit, as frames
#   allocate nothing.
# --use abort=: no `abort` import. The host only provides
#   wasi_snapshot_preview1; a failed bounds check still traps (unreachable).
# --exportStart _initialize: the top-level code (sine table, palettes) runs
#   when the host calls _initialize, the WASI reactor convention.
# -O3 --noAssert: speed over size, assert() compiled out. Bounds checks on
#   array accesses stay wherever the code does not say unchecked().
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/ports/assemblyscript"
cd "$here"
if [ ! -x node_modules/.bin/asc ]; then
  if [ -f package-lock.json ]; then npm ci --silent; else npm install --silent; fi
fi
mkdir -p "$root/web/public/wasm"
node_modules/.bin/asc assembly/index.ts \
  --runtime minimal \
  --use abort= \
  --exportStart _initialize \
  -O3 --noAssert \
  -o "$root/web/public/wasm/assemblyscript.wasm"
