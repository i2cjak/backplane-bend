#!/bin/sh
# Build a Bend program to a native binary in parallel, gently.
#
#   scripts/build-app.sh src/app/main.bend build/backplane
#
# `bend X -o bin` compiles one ~30 MB C file on one core (minutes, ~20 GB).
# Here bend emits the C, scripts/cc-split.py deals it into units, and clang
# compiles them side by side at low priority, so the machine stays usable.
# Builds on this machine share one lock (/tmp/bp-wt-build.lock, as the
# agents' builds do), so only one runs at a time, and stay on 4 cores.
#   BACKPLANE_JOBS  parallel compiles (default 4)
#   BACKPLANE_CPUS  the cores builds may use (default 0-3; "" for any)
#   BACKPLANE_UNITS the units the C is split into (default: two per job);
#                   a unit's clang peak follows its size: 16 units ~4.5 GB
#                   each, 48 ~2 GB (docs/ci.md)
#   BACKPLANE_CFLAGS  (default: -O3, as bend -o)
#   BACKPLANE_CC_CACHE  a directory of binaries keyed by their emitted C:
#                   when bend emits the same C again, clang is skipped (CI)
set -eu
# (a caller already inside `flock /tmp/bp-wt-build.lock ...` holds it)
held() {
  p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    case $(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) in
      *flock*bp-wt-build.lock*) return 0 ;;
    esac
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
  done
  return 1
}
if [ -z "${BP_BUILD_LOCKED:-}" ] && command -v flock >/dev/null 2>&1 && ! held; then
  BP_BUILD_LOCKED=1 exec flock /tmp/bp-wt-build.lock "$0" "$@"
fi
src=$1
out=$2
cd "$(dirname "$0")/.."
jobs=${BACKPLANE_JOBS:-4}
# bend is a Bun program: JavaScriptCore sizes its heap to the machine's RAM
# and let the app's emit grow past 28 GB (systemd-oomd then killed whole
# desktop sessions). Told the machine has 12 GB, it peaks near 12 GB and
# takes a few seconds longer.
export BUN_JSC_forceRAMSize=${BUN_JSC_forceRAMSize:-12884901888}
cpus=${BACKPLANE_CPUS-0-3}
pin=""
if [ -n "$cpus" ] && command -v taskset >/dev/null 2>&1; then
  pin="taskset -c $cpus"
fi
cflags=${BACKPLANE_CFLAGS:--O3}
CC=${CC:-clang}
export CC
work="build/cc/$(basename "$out")"
mkdir -p "$work"
# bend's own emit runs on every core; keep it polite too
nice -n 19 $pin bend "$src" -o "$work/all.c" >/dev/null
cached=""
if [ -n "${BACKPLANE_CC_CACHE:-}" ]; then
  mkdir -p "$BACKPLANE_CC_CACHE"
  key=$( { cat "$work/all.c"; echo "$cflags"; "$CC" --version; uname -m; } | sha256sum | cut -c1-40)
  cached="$BACKPLANE_CC_CACHE/$key"
  if [ -f "$cached" ]; then
    cp "$cached" "$out"
    touch "$cached"
    echo "$out (same C as before: from $BACKPLANE_CC_CACHE)"
    exit 0
  fi
fi
n=$(nice -n 19 python3 scripts/cc-split.py "$work/all.c" "$work" "${BACKPLANE_UNITS:-$(( jobs * 2 ))}")
rm -f "$work"/u*.o
ls "$work"/u*.c | nice -n 19 $pin xargs -P "$jobs" -I{} sh -c \
  '"$CC" -std=c11 '"$cflags"' -w -c "$1" -o "${1%.c}.o" || { echo "cc failed: $1" >&2; exit 255; }' _ {}
# the libraries bend -o links: X11 and ALSA when an effect includes them
libs=""
grep -q '#include <X11/' "$work/all.c" && libs="$libs -lX11"
grep -q '#include <alsa/' "$work/all.c" && libs="$libs -lasound"
nice -n 19 $pin "$CC" $cflags "$work"/u*.o -o "$out" -lpthread -lm $libs
if [ -n "$cached" ]; then
  cp "$out" "$cached.$$" && mv "$cached.$$" "$cached"
  # the newest 24 binaries are plenty (two per build)
  ls -1t "$BACKPLANE_CC_CACHE" | tail -n +25 | while read -r f; do rm -f "$BACKPLANE_CC_CACHE/$f"; done
fi
echo "$out ($n units, $jobs jobs)"
