#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/stop-subtitle-watcher.sh" || true
"$SCRIPT_DIR/stop-hls-proxy.sh" || true
