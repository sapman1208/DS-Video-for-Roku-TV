#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WATCHER_JS="${ROKU_SUBTITLE_WATCHER_JS:-$SCRIPT_DIR/subtitle-watcher.js}"
LOG_FILE="${ROKU_SUBTITLE_LOG:-/tmp/roku-subtitle-watcher.log}"
PID_FILE="${ROKU_SUBTITLE_PID:-/tmp/roku-subtitle-watcher.pid}"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  . "$SCRIPT_DIR/.env"
  set +a
fi

export ROKU_SUBTITLE_POLL_SECONDS="${ROKU_SUBTITLE_POLL_SECONDS:-900}"

if [ -z "${NODE_BIN:-}" ]; then
  if command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
  elif [ -x /volume1/@appstore/homebridge/app/bin/node ]; then
    NODE_BIN=/volume1/@appstore/homebridge/app/bin/node
  elif [ -x /var/packages/Node.js_v20/target/usr/local/bin/node ]; then
    NODE_BIN=/var/packages/Node.js_v20/target/usr/local/bin/node
  elif [ -x /var/packages/Node.js_v18/target/usr/local/bin/node ]; then
    NODE_BIN=/var/packages/Node.js_v18/target/usr/local/bin/node
  else
    echo "node not found. Set NODE_BIN=/path/to/node before starting." >&2
    exit 1
  fi
fi

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "roku-subtitle-watcher already running with pid $(cat "$PID_FILE")"
  exit 0
fi

if [ ! -f "$WATCHER_JS" ]; then
  echo "Cannot find subtitle-watcher.js at: $WATCHER_JS" >&2
  exit 1
fi

nohup "$NODE_BIN" "$WATCHER_JS" --watch >>"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
echo "started roku-subtitle-watcher pid $(cat "$PID_FILE")"
echo "node: $NODE_BIN"
echo "log: $LOG_FILE"
