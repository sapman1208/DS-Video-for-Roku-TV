#!/bin/sh
set -eu

PKG_DEST="${1:-}"
WRAPPER="$PKG_DEST/extras/ffmpeg41-wrapper-DSM7_X-Advanced"

if [ ! -f "$WRAPPER" ]; then
  echo "No optional Video Station ffmpeg wrapper found; skipping wrapper install."
  exit 0
fi

echo "Optional wrapper file found at $WRAPPER, but automatic wrapper patching is disabled."
echo "Review and install wrapper patches manually because they modify Synology package internals."

