#!/bin/sh
set -eu

PID_FILE="${ROKU_CONVERT_PID:-/tmp/roku-library-converter.pid}"

if [ ! -f "$PID_FILE" ]; then
  echo "roku-library-converter is not running"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "stopped roku-library-converter pid $PID"
fi

rm -f "$PID_FILE"
rm -f "${ROKU_CONVERT_LOCK:-/tmp/roku-library-converter.lock}"
