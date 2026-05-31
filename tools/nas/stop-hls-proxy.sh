#!/bin/sh
set -eu

PID_FILE="${ROKU_HLS_PID:-/tmp/roku-hls-proxy.pid}"

if [ ! -f "$PID_FILE" ]; then
  echo "roku-hls-proxy is not running"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "stopped roku-hls-proxy pid $PID"
fi

rm -f "$PID_FILE"
