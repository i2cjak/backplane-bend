#!/bin/sh
# One-time host setup for building Backplane (Bend) locally. Run with sudo.
#   clang/lld : native Bend builds (Bend needs clang 19+; CI uses the same)
#   kicad     : kicad-cli for ERC/DRC/exports and viewer fixtures
set -eu
apt-get update
apt-get install -y clang lld kicad
clang --version | head -1
kicad-cli --version
