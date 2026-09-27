#!/bin/sh
# Run every test program. A test prints lines "ok ..." or "FAIL ..." and the
# script fails when any FAIL appears or a test exits non-zero. Tests run
# side by side (BEND_JOBS at once, default half the cores) and report in order.
set -eu
cd "$(dirname "$0")/.."
jobs=${BEND_JOBS:-$(( $(nproc) / 2 ))}
[ "$jobs" -ge 1 ] || jobs=1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ls test/*_test.bend | xargs -P "$jobs" -I{} sh -c \
  'o="$2/$(basename "$1")"; bend "$1" > "$o" 2>&1 && : > "$o.ok" || true' _ {} "$tmp"
status=0
for t in test/*_test.bend; do
  o="$tmp/$(basename "$t")"
  out=$(cat "$o")
  [ -e "$o.ok" ] || { echo "$t: exited non-zero"; echo "$out"; status=1; continue; }
  # a program that does not check prints its errors and still exits 0
  printf '%s\n' "$out" | grep -q '^ok ' && ! printf '%s\n' "$out" | grep -q '^Error:' || { echo "$t: did not run"; printf '%s\n' "$out" | head -20; status=1; continue; }
  printf '%s\n' "$out" | grep -q '^FAIL' && { echo "$t:"; printf '%s\n' "$out" | grep '^FAIL'; status=1; } || echo "$t: ok"
done
exit $status
