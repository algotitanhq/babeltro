#!/bin/sh
# Builds every port and the lab, then deploys web/dist to the babeltro
# Worker. The Perl interpreter is fetched first (pinned and checked).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/ports/perl/fetch.sh"
"$root/scripts/build-all.sh"
cd "$root/web"
npm ci --silent
for d in "$root"/ports/*/; do
  [ -f "$d/package.json" ] && [ -f "$d/port.js" ] && (cd "$d" && npm ci --silent)
done
npx vite build
npx wrangler deploy
