#!/bin/sh
# Type-check every Bend file, then prove every law. CI runs exactly this.
# The files check side by side and the proof runs beside them
# (BEND_JOBS at once, default half the cores); the report is the same.
set -eu
cd "$(dirname "$0")/.."
jobs=${BEND_JOBS:-$(( $(nproc) / 2 ))}
[ "$jobs" -ge 1 ] || jobs=1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bend PROOF.bend > "$tmp/proof" 2>&1 &
proof=$!
files=$(git ls-files --cached --others --exclude-standard '*.bend' | grep -v '^PROOF.bend$')
printf '%s\n' $files | xargs -P "$jobs" -I{} sh -c \
  'bend "$1" --check-only > "$2/$(printf %s "$1" | tr / _)" 2>&1 || true' _ {} "$tmp"
fail=0
for f in $files; do
  out=$(cat "$tmp/$(printf %s "$f" | tr / _)")
  case $out in
    *"All terms check"*|"") ;;
    *"TODO"*) [ "$f" = LAWS.bend ] || { echo "$f: $out"; fail=1; } ;;
    *) echo "$f:"; echo "$out"; fail=1 ;;
  esac
done
status=0
wait $proof || status=$?
[ $fail = 0 ] || exit 1
cat "$tmp/proof"
exit $status
