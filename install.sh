#!/bin/sh
set -eu

BRANCH="${BRANCH:-main}"
REPO="${REPO:-sapman1208/DS-Video-for-Roku-TV}"
INSTALL_DIR="${INSTALL_DIR:-/tmp/ds-video-restore-kit}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp/ds-video-restore-kit-download}"
RUN_RESTORE=1
PYTHON_BIN="${PYTHON_BIN:-}"
INSECURE_FLAG=""
RESTORE_ARGS=""

usage() {
  cat <<EOF
Usage: sh install.sh [options]

Downloads this repository's restore-kit tools into:
  $INSTALL_DIR

Options:
  --run                 Run the restore after downloading SPKs. This is default.
  --no-run              Download and prepare only.
  --install-dir=PATH    Install restore-kit tools somewhere else.
  --download-dir=PATH   Store downloaded SPKs somewhere else.
  --branch=NAME         GitHub branch to download. Default: main.
  --insecure            Pass --insecure to the Python downloader.
  --restore-args=ARGS   Extra args for ds-video-restore-kit.sh when --run is used.
  -h, --help            Show this help.

Examples:
  sh install.sh
  sh install.sh --no-run
  sh install.sh --run
  sh install.sh --run --restore-args="--dsm-http-port=5000 --dsm-https-port=5001 --debug"
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN_RESTORE=1 ;;
    --no-run) RUN_RESTORE=0 ;;
    --install-dir=*) INSTALL_DIR=${1#*=} ;;
    --download-dir=*) DOWNLOAD_DIR=${1#*=} ;;
    --branch=*) BRANCH=${1#*=} ;;
    --insecure) INSECURE_FLAG="--insecure" ;;
    --restore-args=*) RESTORE_ARGS=${1#*=} ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

find_python() {
  if [ -n "$PYTHON_BIN" ]; then
    echo "$PYTHON_BIN"
    return 0
  fi
  for candidate in python3 /usr/bin/python3 /usr/local/bin/python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

download() {
  url="$1"
  output="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -L -o "$output" "$url"
  else
    echo "ERROR: missing wget or curl." >&2
    exit 1
  fi
}

PYTHON_BIN=$(find_python || true)
if [ -z "$PYTHON_BIN" ]; then
  echo "ERROR: missing Python 3. Install Python 3 or set PYTHON_BIN=/path/to/python3." >&2
  exit 1
fi

WORK_DIR="/tmp/ds-video-restore-kit-bootstrap.$$"
ARCHIVE="$WORK_DIR/source.tar.gz"
SOURCE_DIR="$WORK_DIR/DS-Video-for-Roku-TV-$BRANCH"
URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "Downloading $URL"
download "$URL" "$ARCHIVE"

echo "Extracting restore-kit tools"
tar -xzf "$ARCHIVE" -C "$WORK_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -R "$SOURCE_DIR/tools/." "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ds-video-restore-kit.sh" "$INSTALL_DIR/build-ds-video-restore-kit.py"

echo "Downloading Synology SPKs for this NAS architecture"
cd "$INSTALL_DIR"
"$PYTHON_BIN" build-ds-video-restore-kit.py --output "$DOWNLOAD_DIR" --arch auto --include-optional --no-archive $INSECURE_FLAG
rm -rf "$INSTALL_DIR/packages"
cp -R "$DOWNLOAD_DIR/restore-kit/packages" "$INSTALL_DIR/"

echo ""
echo "Restore kit ready:"
echo "  $INSTALL_DIR"
echo ""

if [ "$RUN_RESTORE" = "1" ]; then
  LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log"
  echo "Running restore. Log: $LOG"
  # shellcheck disable=SC2086
  LOG="$LOG" /bin/sh "$INSTALL_DIR/ds-video-restore-kit.sh" --debug $RESTORE_ARGS
else
  cat <<EOF
Run restore manually with:
  LOG="/tmp/ds-video-restore-kit-\$(date +%Y%m%d-%H%M%S).log" /bin/sh "$INSTALL_DIR/ds-video-restore-kit.sh" --debug

After restore, open Package Center > Advanced Media Extensions / CodecPack,
then sign in/install the codec entitlement before testing AVI, HEVC, or AVC.
EOF
fi

rm -rf "$WORK_DIR"
