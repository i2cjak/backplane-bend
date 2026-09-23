#!/bin/sh
# Build the native server and the web bundle into dist/.
#   dist/backplane      the server (serves dist/web next to it)
#   dist/web/           index.html + bundled JS/CSS
set -eu
cd "$(dirname "$0")/.."
for f in src/web/app.bend src/server/main.bend; do
  out=$(bend "$f" --check-only 2>&1) || { echo "$out"; exit 1; }
  case $out in *"All terms check"*) ;; *) echo "$out"; exit 1 ;; esac
done
rm -rf dist
mkdir -p dist
bend src/web/index.html -o dist/web
bend src/server/main.bend -o dist/backplane
cp dist/backplane build/backplane 2>/dev/null || { mkdir -p build; cp dist/backplane build/backplane; }
ls -la dist dist/web
