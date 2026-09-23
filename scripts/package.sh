#!/bin/sh
# Package dist/ into dist/backplane-<version>-<os>-<arch>.tar.gz:
#   backplane-<os>-<arch>/{backplane, backplane-serve, web/}
#   scripts/package.sh v0.2.0 linux-x64
set -eu
cd "$(dirname "$0")/.."
ver=$1 plat=$2
dir="dist/pkg/backplane-$plat"
rm -rf dist/pkg && mkdir -p "$dir"
cp dist/backplane dist/backplane-serve "$dir/"
cp -R dist/web "$dir/web"
tar -czf "dist/backplane-$ver-$plat.tar.gz" -C dist/pkg "backplane-$plat"
ls -la "dist/backplane-$ver-$plat.tar.gz"
