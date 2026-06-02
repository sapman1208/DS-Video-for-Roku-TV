#!/bin/sh
set -eu

usage() {
  echo "Usage: SYNO_HOST=host SYNO_USER=admin [SYNO_PASSWORD=password] sh synology-spk/install-via-ssh.sh [path/to/RokuDSVideoTools.spk]" >&2
  exit 2
}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SPK="${1:-$ROOT/synology-spk/out/RokuDSVideoTools-1.8.0.spk}"
SYNO_HOST="${SYNO_HOST:-}"
SYNO_USER="${SYNO_USER:-}"
SYNO_PASSWORD="${SYNO_PASSWORD:-}"
REMOTE_SPK="/tmp/RokuDSVideoTools.spk"
REMOTE_INSTALLER="/tmp/roku-ds-video-tools-install.sh"
VIDEO_STATION_INSTALL="${SYNO_INSTALL_VIDEO_STATION:-}"

[ -n "$SYNO_HOST" ] || usage
[ -n "$SYNO_USER" ] || usage
[ -f "$SPK" ] || {
  echo "SPK not found: $SPK" >&2
  echo "Build it first with: sh synology-spk/build-spk.sh" >&2
  exit 1
}

ssh_cmd() {
  if [ -n "$SYNO_PASSWORD" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$SYNO_PASSWORD" ssh -o StrictHostKeyChecking=no "$SYNO_USER@$SYNO_HOST" "$@"
  else
    ssh -o StrictHostKeyChecking=no "$SYNO_USER@$SYNO_HOST" "$@"
  fi
}

scp_file() {
  src="$1"
  dest="$2"
  if [ -n "$SYNO_PASSWORD" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$SYNO_PASSWORD" scp -o StrictHostKeyChecking=no "$src" "$SYNO_USER@$SYNO_HOST:$dest"
  else
    scp -o StrictHostKeyChecking=no "$src" "$SYNO_USER@$SYNO_HOST:$dest"
  fi
}

sudo_remote() {
  if [ -n "$SYNO_PASSWORD" ]; then
    escaped=$(printf "%s" "$SYNO_PASSWORD" | sed "s/'/'\\\\''/g")
    ssh_cmd "printf '%s\n' '$escaped' | sudo -S -p '' sh -c '$1'"
  else
    ssh_cmd "sudo sh -c '$1'"
  fi
}

quote_sh() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

LOCAL_INSTALLER="${TMPDIR:-/tmp}/roku-ds-video-tools-install.$$"
trap 'rm -f "$LOCAL_INSTALLER"' EXIT

{
  echo "#!/bin/sh"
  echo "set -eu"
  echo "INSTALL_USER=$(quote_sh "$SYNO_USER")"
  echo "REMOTE_SPK=$(quote_sh "$REMOTE_SPK")"
  echo "VIDEO_STATION_INSTALL=$(quote_sh "$VIDEO_STATION_INSTALL")"
  cat <<'INSTALLER'
SYNOPKG=/usr/syno/bin/synopkg
volume=$(ls -1d /volume[0-9]* 2>/dev/null | sed "s#^/##" | head -n 1)
if [ -z "$volume" ]; then
  volume=volume1
fi

if ! "$SYNOPKG" list --name 2>/dev/null | grep -qx "Node.js_v22"; then
  echo "Installing Node.js_v22 from Synology package server on $volume..."
  "$SYNOPKG" install_from_server Node.js_v22 "$volume" "$INSTALL_USER" false
else
  echo "Node.js_v22 already installed."
fi

if [ -n "$VIDEO_STATION_INSTALL" ]; then
  case "$VIDEO_STATION_INSTALL" in
    all|novs|noms|onlyamc)
      echo "Installing Video Station support with option: $VIDEO_STATION_INSTALL"
      if [ -x /var/packages/RokuDSVideoTools/target/tools/nas/videostation_for_722.sh ]; then
        /var/packages/RokuDSVideoTools/target/tools/nas/videostation_for_722.sh --install="$VIDEO_STATION_INSTALL"
      else
        echo "Video Station helper is not installed yet; will run after RokuDSVideoTools install."
      fi
      ;;
    *)
      echo "Invalid SYNO_INSTALL_VIDEO_STATION value: $VIDEO_STATION_INSTALL" >&2
      echo "Use one of: all, novs, noms, onlyamc" >&2
      exit 2
      ;;
  esac
fi

echo "Installing RokuDSVideoTools..."
"$SYNOPKG" install "$REMOTE_SPK"

if [ -n "$VIDEO_STATION_INSTALL" ]; then
  if [ -x /var/packages/RokuDSVideoTools/target/tools/nas/videostation_for_722.sh ]; then
    /var/packages/RokuDSVideoTools/target/tools/nas/videostation_for_722.sh --install="$VIDEO_STATION_INSTALL"
  fi
fi

"$SYNOPKG" start RokuDSVideoTools || "$SYNOPKG" resume RokuDSVideoTools || true
"$SYNOPKG" status RokuDSVideoTools || true
INSTALLER
} >"$LOCAL_INSTALLER"

echo "Uploading $SPK to $SYNO_HOST:$REMOTE_SPK"
scp_file "$SPK" "$REMOTE_SPK"
scp_file "$LOCAL_INSTALLER" "$REMOTE_INSTALLER"

echo "Installing dependencies and Roku DS Video Tools on $SYNO_HOST"
sudo_remote "sh $REMOTE_INSTALLER"
