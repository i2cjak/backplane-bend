#!/bin/sh
# Type-check every Bend file, then prove every law. CI runs exactly this.
set -eu
cd "$(dirname "$0")/.."
fail=0
for f in $(git ls-files --cached --others --exclude-standard '*.bend' | grep -v '^PROOF.bend$'); do
  out=$(bend "$f" --check-only 2>&1) || true
  case $out in
    *"All terms check."*|"") ;;
    *"TODO"*) [ "$f" = LAWS.bend ] || { echo "$f: $out"; fail=1; } ;;
    *) echo "$f:"; echo "$out"; fail=1 ;;
  esac
done
[ $fail = 0 ] || exit 1
bend PROOF.bend
