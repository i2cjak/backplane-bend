#!/bin/sh
# Build into dist/:
#   dist/backplane        the app: native window + hub + web server
#   dist/backplane-serve  hub + web server only (no X11 needed)
#   dist/web/             the web client (for other devices)
# X11 headers: /usr/include (libx11-dev), or BACKPLANE_X11=<prefix> holding
# include/ and lib/libX11.so (see AGENTS.md).
set -eu
cd "$(dirname "$0")/.."
for f in src/web/app.bend src/server/main.bend src/app/main.bend; do
  out=$(bend "$f" --check-only 2>&1) || { echo "$out"; exit 1; }
  case $out in *"All terms check"*) ;; *) echo "$out"; exit 1 ;; esac
done
if [ -n "${BACKPLANE_X11:-}" ]; then
  export CPATH="$BACKPLANE_X11/include${CPATH:+:$CPATH}"
  export LIBRARY_PATH="$BACKPLANE_X11/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
fi
# a release build stamps its version (BACKPLANE_VERSION=v1.2.3)
if [ -n "${BACKPLANE_VERSION:-}" ]; then
  printf 'import Base\n\n# The running build'"'"'s version (stamped by scripts/build.sh).\n\ndef Version.current() -> String:\n  "%s"\n' "${BACKPLANE_VERSION#v}" > src/core/version.bend
fi
rm -rf dist
mkdir -p dist build
bend src/web/index.html -o dist/web
bend src/server/main.bend -o dist/backplane-serve
bend src/app/main.bend -o dist/backplane
cp dist/backplane build/backplane
ls -la dist
