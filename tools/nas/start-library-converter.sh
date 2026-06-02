#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONVERTER_JS="${ROKU_CONVERTER_JS:-$SCRIPT_DIR/library-converter.js}"
LOG_FILE="${ROKU_CONVERT_LOG:-/tmp/roku-library-converter.log}"
PID_FILE="${ROKU_CONVERT_PID:-/tmp/roku-library-converter.pid}"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  . "$SCRIPT_DIR/.env"
  set +a
fi

export ROKU_CONVERT_POLL_SECONDS="${ROKU_CONVERT_POLL_SECONDS:-900}"
export ROKU_CONVERT_DELETE_ORIGINAL="${ROKU_CONVERT_DELETE_ORIGINAL:-1}"

# Optional subtitles. Set OPEN_SUBTITLES_API_KEY, and optionally
# OPEN_SUBTITLES_USERNAME/OPEN_SUBTITLES_PASSWORD, before starting.

if [ -z "${FFMPEG:-}" ]; then
  if [ -x /var/packages/ffmpeg7/target/bin/ffmpeg ]; then
    export FFMPEG=/var/packages/ffmpeg7/target/bin/ffmpeg
  elif [ -x /var/packages/ffmpeg/target/bin/ffmpeg ]; then
    export FFMPEG=/var/packages/ffmpeg/target/bin/ffmpeg
  elif [ -x /var/packages/VideoStation/target/bin/ffmpeg ]; then
    export FFMPEG=/var/packages/VideoStation/target/bin/ffmpeg
  elif [ -x /var/packages/VideoStation/target/lib/ffmpeg ]; then
    export FFMPEG=/var/packages/VideoStation/target/lib/ffmpeg
  elif command -v ffmpeg >/dev/null 2>&1; then
    export FFMPEG="$(command -v ffmpeg)"
  else
    echo "ffmpeg not found. Install SynoCommunity ffmpeg7, Video Station, or set FFMPEG=/path/to/ffmpeg before starting." >&2
    exit 1
  fi
fi

if [ -z "${NODE_BIN:-}" ]; then
  if command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
  elif [ -x /volume1/@appstore/homebridge/app/bin/node ]; then
    NODE_BIN=/volume1/@appstore/homebridge/app/bin/node
  elif [ -x /var/packages/Node.js_v22/target/usr/local/bin/node ]; then
    NODE_BIN=/var/packages/Node.js_v22/target/usr/local/bin/node
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
  echo "roku-library-converter already running with pid $(cat "$PID_FILE")"
  exit 0
fi

if [ ! -f "$CONVERTER_JS" ]; then
  echo "Cannot find library-converter.js at: $CONVERTER_JS" >&2
  exit 1
fi

nohup "$NODE_BIN" "$CONVERTER_JS" --watch --delete-original >>"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
echo "started roku-library-converter pid $(cat "$PID_FILE")"
echo "ffmpeg: $FFMPEG"
echo "node: $NODE_BIN"
echo "log: $LOG_FILE"
