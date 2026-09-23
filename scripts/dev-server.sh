#!/bin/sh
# Start/stop a throwaway dev server. The PID is recorded, so stop kills
# exactly that process (never by name).
#   scripts/dev-server.sh start [port] [home]   # default 3799, /tmp/bp-dev
#   scripts/dev-server.sh stop  [port]
set -eu
cd "$(dirname "$0")/.."
cmd=${1:-start}
port=${2:-3799}
home=${3:-/tmp/bp-dev}
pidfile="/tmp/backplane-dev-$port.pid"
case $cmd in
  start)
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
    web=${BACKPLANE_WEB:-dist/web}
    ./build/backplane --web "$web" --home "$home" --port "$port" > "/tmp/backplane-dev-$port.log" 2>&1 &
    echo $! > "$pidfile"
    sleep 0.5
    cat "/tmp/backplane-dev-$port.log"
    ;;
  stop)
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
    ;;
esac
