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
#   BACKPLANE_CFLAGS  (default: -O3, as bend -o)
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
n=$(nice -n 19 python3 scripts/cc-split.py "$work/all.c" "$work" "$(( jobs * 2 ))")
rm -f "$work"/u*.o
ls "$work"/u*.c | nice -n 19 $pin xargs -P "$jobs" -I{} sh -c \
  '"$CC" -std=c11 '"$cflags"' -w -c "$1" -o "${1%.c}.o" || { echo "cc failed: $1" >&2; exit 255; }' _ {}
# the libraries bend -o links: X11 and ALSA when an effect includes them
libs=""
grep -q '#include <X11/' "$work/all.c" && libs="$libs -lX11"
grep -q '#include <alsa/' "$work/all.c" && libs="$libs -lasound"
nice -n 19 $pin "$CC" $cflags "$work"/u*.o -o "$out" -lpthread -lm $libs
echo "$out ($n units, $jobs jobs)"
