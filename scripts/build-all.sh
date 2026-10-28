#!/bin/sh
# Builds the Go reference and every port that has a build script
# (ports/<lang>/build.sh writes web/public/wasm/<lang>.wasm). Ports that run
# as JavaScript modules have nothing to build.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/scripts/build-go.sh"
for script in "$root"/ports/*/build.sh; do
  echo "building $(basename "$(dirname "$script")")"
  "$script"
done
