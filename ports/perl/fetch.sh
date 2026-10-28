#!/bin/sh
# Fetches the Perl interpreter this port runs on: zeroperl, Perl 5 compiled
# to WebAssembly (WASI + Asyncify), as published on npm by its authors
# (https://github.com/6over3/zeroperl-ts, Apache-2.0). We take the npm
# tarball itself, check it against a pinned SHA-256 and unpack only the ES
# module and the wasm into vendor/. Nothing is installed and no package
# script runs.
set -eu

VERSION=1.0.10
URL="https://registry.npmjs.org/@6over3/zeroperl-ts/-/zeroperl-ts-$VERSION.tgz"
SHA256=c46c5ffff4f2c2216137a6b34b4eb03f5554e17a2b88979463c5f61dffb36fed

cd "$(dirname "$0")"
out=vendor/zeroperl-ts
if [ -f "$out/VERSION" ] && [ "$(cat "$out/VERSION")" = "$VERSION" ]; then
  echo "zeroperl-ts $VERSION already in $out"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/pkg.tgz" "$URL"
got=$(shasum -a 256 "$tmp/pkg.tgz" | cut -d' ' -f1)
if [ "$got" != "$SHA256" ]; then
  echo "SHA-256 mismatch for $URL" >&2
  echo "  expected $SHA256" >&2
  echo "  got      $got" >&2
  exit 1
fi

tar -xzf "$tmp/pkg.tgz" -C "$tmp" \
  package/package.json package/README.md \
  package/dist/esm/index.js package/dist/esm/zeroperl.wasm
rm -rf "$out"
mkdir -p "$out"
cp "$tmp/package/package.json" "$tmp/package/README.md" \
   "$tmp/package/dist/esm/index.js" "$tmp/package/dist/esm/zeroperl.wasm" "$out/"
echo "$VERSION" > "$out/VERSION"
echo "zeroperl-ts $VERSION -> $out ($(wc -c < "$out/zeroperl.wasm" | tr -d ' ') bytes of wasm)"
