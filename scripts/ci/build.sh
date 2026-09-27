#!/bin/sh
# CI's build: scripts/build.sh, reusing a dist/ built earlier from the same
# sources when BP_CI_CACHE is set (the self-hosted runners, docs/ci.md). A
# merge to main builds the tree its PR already built, so it is instant.
# Binaries whose emitted C did not change skip clang (BACKPLANE_CC_CACHE).
set -eu
cd "$(dirname "$0")/../.."
[ -n "${BP_CI_CACHE:-}" ] || exec scripts/build.sh
store="$BP_CI_CACHE/build"
mkdir -p "$store/dist"
bun=$(command -v bun || echo "$HOME/.bun/bin/bun")
key=$( {
  git ls-tree -r HEAD -- src scripts tools patches assets
  echo "bend ${BEND_VERSION:-$(sha256sum "$(command -v bend)")}"
  "${CC:-clang}" --version
  "$bun" --version 2>/dev/null || echo "no bun"
  uname -m
  env | grep -E '^BACKPLANE_(VERSION|CFLAGS)=' || true
} | sha256sum | cut -c1-40)
hit="$store/dist/$key"
if [ -d "$hit" ]; then
  rm -rf dist && cp -a "$hit" dist
  mkdir -p build && cp dist/backplane build/backplane
  touch "$hit"
  echo "dist/ from an earlier build of the same sources ($key)"
  exit 0
fi
BACKPLANE_CC_CACHE="$store/cc" scripts/build.sh
cp -a dist "$hit.$$" && mv "$hit.$$" "$hit" || rm -rf "$hit.$$"
# keep the newest 8 (about 300 MB each)
ls -1t "$store/dist" | tail -n +9 | while read -r d; do rm -rf "${store:?}/dist/$d"; done
