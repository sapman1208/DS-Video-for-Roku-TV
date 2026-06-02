#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SPK_ROOT="$ROOT/synology-spk"
VERSION="${VERSION:-1.8.0}"
PACKAGE="RokuDSVideoTools"
BUILD="$SPK_ROOT/.build"
PKGDIR="$BUILD/package"
OUT="$SPK_ROOT/out"

rm -rf "$BUILD"
mkdir -p "$BUILD/scripts" "$BUILD/conf" "$PKGDIR/tools/nas" "$PKGDIR/config" "$PKGDIR/extras" "$OUT"

copy_tool() {
  src="$ROOT/tools/$1"
  dest="$PKGDIR/tools/$1"
  if [ ! -f "$src" ]; then
    echo "missing required tool: $src" >&2
    exit 1
  fi
  cp "$src" "$dest"
}

copy_nas_script() {
  src="$ROOT/tools/nas/$1"
  dest="$PKGDIR/tools/nas/$1"
  if [ ! -f "$src" ]; then
    echo "missing required NAS script: $src" >&2
    exit 1
  fi
  cp "$src" "$dest"
  chmod 755 "$dest"
}

copy_tool ffmpeg-hls-proxy.js
copy_tool library-converter.js
copy_tool subtitle-watcher.js
copy_tool download-subtitles.js
copy_tool generate-vsmeta.js
copy_tool migrate-transcodes.js
copy_tool normalize-media-plan.js
copy_tool apply-normalize-plan.js
copy_tool cleanup-normalize-leftovers.js
copy_tool generate-episode-posters.js
if [ -f "$ROOT/tools/vsmeta-overrides.json" ]; then
  copy_tool vsmeta-overrides.json
else
  printf '{}\n' > "$PKGDIR/tools/vsmeta-overrides.json"
fi

copy_nas_script start-hls-proxy.sh
copy_nas_script stop-hls-proxy.sh
copy_nas_script start-subtitle-watcher.sh
copy_nas_script stop-subtitle-watcher.sh
copy_nas_script start-library-converter.sh
copy_nas_script stop-library-converter.sh
copy_nas_script start-on-demand.sh
copy_nas_script stop-on-demand.sh
copy_nas_script start-full-automation.sh
copy_nas_script stop-full-automation.sh

cp "$SPK_ROOT/package/config/config.env.example" "$PKGDIR/config/config.env.example"
cp "$SPK_ROOT/package/tools/nas/install-videostation-if-needed.sh" "$PKGDIR/tools/nas/install-videostation-if-needed.sh"
cp "$SPK_ROOT/package/tools/nas/install-videostation-wrapper.sh" "$PKGDIR/tools/nas/install-videostation-wrapper.sh"
chmod 755 "$PKGDIR/tools/nas/install-videostation-if-needed.sh" "$PKGDIR/tools/nas/install-videostation-wrapper.sh"

if [ -f "$SPK_ROOT/package/extras/VideoStation.spk" ]; then
  cp "$SPK_ROOT/package/extras/VideoStation.spk" "$PKGDIR/extras/VideoStation.spk"
fi
if [ -f "$SPK_ROOT/package/extras/ffmpeg41-wrapper-DSM7_X-Advanced" ]; then
  cp "$SPK_ROOT/package/extras/ffmpeg41-wrapper-DSM7_X-Advanced" "$PKGDIR/extras/ffmpeg41-wrapper-DSM7_X-Advanced"
fi

cp "$SPK_ROOT/spk/scripts/start-stop-status" "$BUILD/scripts/start-stop-status"
cp "$SPK_ROOT/spk/scripts/postinst" "$BUILD/scripts/postinst"
cp "$SPK_ROOT/spk/scripts/preuninst" "$BUILD/scripts/preuninst"
cp "$SPK_ROOT/spk/conf/privilege" "$BUILD/conf/privilege"
chmod 755 "$BUILD/scripts/start-stop-status" "$BUILD/scripts/postinst" "$BUILD/scripts/preuninst"

sed "s/@VERSION@/$VERSION/g" "$SPK_ROOT/spk/INFO" > "$BUILD/INFO"

(
  cd "$PKGDIR"
  tar -czf "$BUILD/package.tgz" .
)

(
  cd "$BUILD"
  tar -cf "$OUT/$PACKAGE-$VERSION.spk" INFO conf scripts package.tgz
)

echo "$OUT/$PACKAGE-$VERSION.spk"
