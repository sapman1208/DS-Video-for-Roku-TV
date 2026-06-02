#!/bin/sh
set -eu

PKG_DEST="${1:-}"
VIDEO_STATION_SPK="$PKG_DEST/extras/VideoStation.spk"

if [ -d /var/packages/VideoStation ]; then
  echo "Video Station already installed."
  exit 0
fi

if [ ! -f "$VIDEO_STATION_SPK" ]; then
  echo "Video Station not installed and no bundled local VideoStation.spk found."
  echo "Place an official VideoStation.spk in package/extras before building if you want this installer to install it."
  exit 0
fi

if command -v synopkg >/dev/null 2>&1; then
  echo "Installing local Video Station package: $VIDEO_STATION_SPK"
  synopkg install "$VIDEO_STATION_SPK" || true
else
  echo "synopkg command not found; cannot install Video Station automatically."
fi

