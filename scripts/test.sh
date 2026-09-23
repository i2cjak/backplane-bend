#!/bin/sh
# Run every test program. A test prints lines "ok ..." or "FAIL ..." and the
# script fails when any FAIL appears or a test exits non-zero.
set -eu
cd "$(dirname "$0")/.."
status=0
for t in test/*_test.bend; do
  out=$(bend "$t" 2>&1) || { echo "$t: exited non-zero"; echo "$out"; status=1; continue; }
  printf '%s\n' "$out" | grep -q '^FAIL' && { echo "$t:"; printf '%s\n' "$out" | grep '^FAIL'; status=1; } || echo "$t: ok"
done
exit $status
