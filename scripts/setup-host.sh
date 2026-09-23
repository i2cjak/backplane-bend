#!/bin/sh
# One-time host setup for building Backplane (Bend) locally. Run with sudo.
#   clang/lld : native Bend builds (Bend needs clang 19+; CI uses the same)
#   kicad     : kicad-cli for ERC/DRC/exports and viewer fixtures
#   libx11-dev: the native window (X11); xvfb: headless window tests
set -eu
apt-get update
apt-get install -y clang lld kicad libx11-dev xvfb
clang --version | head -1
kicad-cli --version
