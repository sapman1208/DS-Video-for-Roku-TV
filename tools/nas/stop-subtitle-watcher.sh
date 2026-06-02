#!/bin/sh
set -eu

PID_FILE="${ROKU_SUBTITLE_PID:-/tmp/roku-subtitle-watcher.pid}"
if [ ! -f "$PID_FILE" ]; then
  echo "roku-subtitle-watcher is not running"
  rm -f "${ROKU_SUBTITLE_LOCK:-/tmp/roku-subtitle-watcher.lock}"
  exit 0
fi
PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "stopped roku-subtitle-watcher pid $PID"
else
  echo "roku-subtitle-watcher pid $PID was not running"
fi
rm -f "$PID_FILE"
rm -f "${ROKU_SUBTITLE_LOCK:-/tmp/roku-subtitle-watcher.lock}"
