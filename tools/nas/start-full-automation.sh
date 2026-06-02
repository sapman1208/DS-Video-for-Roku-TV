#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/start-hls-proxy.sh"
"$SCRIPT_DIR/start-subtitle-watcher.sh"
"$SCRIPT_DIR/start-library-converter.sh"
