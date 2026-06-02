#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROXY_JS="${ROKU_HLS_PROXY_JS:-$SCRIPT_DIR/ffmpeg-hls-proxy.js}"
LOG_FILE="${ROKU_HLS_LOG:-/tmp/roku-hls-proxy.log}"
PID_FILE="${ROKU_HLS_PID:-/tmp/roku-hls-proxy.pid}"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  . "$SCRIPT_DIR/.env"
  set +a
fi

export ROKU_HLS_HOST="${ROKU_HLS_HOST:-0.0.0.0}"
export ROKU_HLS_PORT="${ROKU_HLS_PORT:-8099}"
export ROKU_HLS_ROOT="${ROKU_HLS_ROOT:-/volume1/@tmp/roku-hls-proxy}"
export ROKU_HLS_SAVE_MP4="${ROKU_HLS_SAVE_MP4:-1}"
export ROKU_HLS_REPLACE_ORIGINAL="${ROKU_HLS_REPLACE_ORIGINAL:-1}"
export ROKU_HLS_DELETE_REPLACED_ORIGINAL="${ROKU_HLS_DELETE_REPLACED_ORIGINAL:-1}"
export ROKU_HLS_MP4_DIR="${ROKU_HLS_MP4_DIR:-/volume1/video/@roku-transcodes}"

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
  echo "roku-hls-proxy already running with pid $(cat "$PID_FILE")"
  exit 0
fi

if [ ! -f "$PROXY_JS" ]; then
  echo "Cannot find ffmpeg-hls-proxy.js at: $PROXY_JS" >&2
  echo "Copy the whole tools folder so the layout is:" >&2
  echo "  tools/ffmpeg-hls-proxy.js" >&2
  echo "  tools/nas/start-hls-proxy.sh" >&2
  exit 1
fi

mkdir -p "$ROKU_HLS_ROOT"
nohup "$NODE_BIN" "$PROXY_JS" >>"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
echo "started roku-hls-proxy pid $(cat "$PID_FILE") on port $ROKU_HLS_PORT"
echo "ffmpeg: $FFMPEG"
echo "node: $NODE_BIN"
echo "log: $LOG_FILE"
