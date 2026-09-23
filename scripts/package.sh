#!/bin/sh
# Package dist/ into dist/backplane-<version>-<os>-<arch>.tar.gz:
#   backplane-<os>-<arch>/{backplane, backplane-serve, web/, helpers, licenses/}
#   scripts/package.sh v0.2.0 linux-x64
set -eu
cd "$(dirname "$0")/.."
ver=$1 plat=$2
dir="dist/pkg/backplane-$plat"
rm -rf dist/pkg && mkdir -p "$dir"
cp dist/backplane dist/backplane-serve LICENSE "$dir/"
cp -R dist/web "$dir/web"
for h in backplane-browser backplane-step2glb; do
  [ -f "dist/$h" ] && cp "dist/$h" "$dir/"
done
[ -d dist/licenses ] && cp -R dist/licenses "$dir/licenses"
tar -czf "dist/backplane-$ver-$plat.tar.gz" -C dist/pkg "backplane-$plat"
ls -la "dist/backplane-$ver-$plat.tar.gz"
