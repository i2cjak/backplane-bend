#!/bin/sh
# Build into dist/:
#   dist/backplane        the app: native window + hub + web server
#   dist/backplane-serve  hub + web server only (no X11 needed)
#   dist/web/             the web client (for other devices)
#   dist/backplane-browser, dist/backplane-step2glb   host helpers (with bun)
# X11 headers: /usr/include (libx11-dev), or BACKPLANE_X11=<prefix> holding
# include/ and lib/libX11.so (see AGENTS.md).
# System fonts (src/gfx/effects/font.c) need no headers and no link flags:
# libfreetype.so.6 and libfontconfig.so.1 are dlopen'd at run time and the
# few FreeType structs read are declared in font.c; without them text falls
# back to the Spleen bitmap font. To re-check those struct layouts against
# real headers without root:
#   apt-get download libfreetype-dev && dpkg -x libfreetype-dev_*.deb ~/.local/ft
#   (headers in ~/.local/ft/usr/include/freetype2; compare offsetof values)
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
cp src/web/sw.js dist/web/sw.js
# precompressed copies: the server sends these to browsers that take gzip
for f in dist/web/*.js dist/web/*.css dist/web/*.html; do gzip -9 -k -n -f "$f"; done
bend src/server/main.bend -o dist/backplane-serve
# the window needs X11 (libX11.so.6, dlopen'd); a Mac has none, so there the
# app always runs as hub + web UI, the same program as backplane-serve. The
# app's one large C file also takes about 20 GB to compile, which a macOS
# runner (7 GB) cannot give; build it only where a window can open
if [ "$(uname -s)" = Darwin ]; then
  cp dist/backplane-serve dist/backplane
else
  bend src/app/main.bend -o dist/backplane
fi
cp dist/backplane build/backplane
# the host helpers (Bun): the agents' browser and STEP -> GLB for the 3D
# viewer; the app runs without them, so a machine without bun skips them
if command -v bun >/dev/null 2>&1 || [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH" scripts/build-browser.sh
  PATH="$HOME/.bun/bin:$PATH" scripts/build-step2glb.sh
else
  echo "bun not found: skipping backplane-browser and backplane-step2glb"
fi
ls -la dist
