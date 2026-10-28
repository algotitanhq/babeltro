#!/bin/sh
# Builds the Go reference as a WebAssembly reactor for the lab.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/web/public/wasm"
cd "$root/go"
GOOS=wasip1 GOARCH=wasm go build -trimpath -buildmode=c-shared \
  -o "$root/web/public/wasm/go.wasm" ./cmd/wasm
