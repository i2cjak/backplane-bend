#!/bin/sh
# Run every test program. A test prints lines "ok ..." or "FAIL ..." and the
# script fails when any FAIL appears or a test exits non-zero.
set -eu
cd "$(dirname "$0")/.."
status=0
for t in test/*_test.bend; do
  out=$(bend "$t" 2>&1) || { echo "$t: exited non-zero"; echo "$out"; status=1; continue; }
  # a program that does not check prints its errors and still exits 0
  printf '%s\n' "$out" | grep -q '^ok ' && ! printf '%s\n' "$out" | grep -q '^Error:' || { echo "$t: did not run"; printf '%s\n' "$out" | head -20; status=1; continue; }
  printf '%s\n' "$out" | grep -q '^FAIL' && { echo "$t:"; printf '%s\n' "$out" | grep '^FAIL'; status=1; } || echo "$t: ok"
done
exit $status
