#!/bin/sh
# Builds the Rust port as a WebAssembly module for the lab.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
# rustup's proxies (cargo, rustc) must be on PATH together; Homebrew's rustup
# does not put them there
command -v cargo >/dev/null || PATH="/opt/homebrew/opt/rustup/bin:$PATH"
mkdir -p "$root/web/public/wasm"
cd "$root/rust"
cargo build --quiet --release --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/babeltro.wasm "$root/web/public/wasm/rust.wasm"
