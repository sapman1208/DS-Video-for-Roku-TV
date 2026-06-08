#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-videostation-rokuvte-wrapper.sh [ssh-target]

Examples:
  install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
  NAS_WEB_BASE=http://10.0.1.80:5000 install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
  NAS_WEB_BASE=https://10.0.1.80:5001 install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
  NAS_HTTP_PORT=5000 NAS_HTTPS_PORT=5001 install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
  NAS_SSH_TARGET=administrator@10.0.1.80 ./tools/install-videostation-rokuvte-wrapper.sh

Installs the Roku Video Station HLS/watch-status wrapper into Synology Video Station.
Run this from macOS, Linux, Windows WSL, or Git Bash. It requires SSH access
with a DSM administrator account that can use sudo to write to
/var/packages/VideoStation/target/ui/webapi.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_WRAPPER="${SCRIPT_DIR}/videostation-rokuvte.cgi"
SSH_TARGET="${1:-${NAS_SSH_TARGET:-administrator@10.0.1.80}}"
REMOTE_TMP="/tmp/rokuvte-wrapper-install.$$"
LOCAL_TMP="$(mktemp -d "${TMPDIR:-/tmp}/rokuvte-wrapper.XXXXXX")"
SSH_USER="${SSH_TARGET%@*}"
REMOTE_ELEVATE="${NAS_ELEVATE:-sudo}"
if [[ "${SSH_USER}" == "${SSH_TARGET}" || "${SSH_USER}" == "root" ]]; then
  REMOTE_ELEVATE=""
fi

cleanup() {
  rm -rf "${LOCAL_TMP}"
}
trap cleanup EXIT

if [[ ! -f "${PY_WRAPPER}" ]]; then
  echo "Missing wrapper source: ${PY_WRAPPER}" >&2
  exit 1
fi

digits_only() {
  printf '%s' "$1" | tr -cd '0-9'
}

prompt_port() {
  local prompt="$1"
  local default_value="$2"
  local value=""
  if [[ -t 0 && -z "${ROKUVTE_NONINTERACTIVE:-}" ]]; then
    read -r -p "${prompt} [${default_value}]: " value
  fi
  value="${value:-${default_value}}"
  digits_only "${value}"
}

NAS_HTTP_PORT="$(digits_only "${NAS_HTTP_PORT:-}")"
NAS_HTTPS_PORT="$(digits_only "${NAS_HTTPS_PORT:-}")"
if [[ -z "${NAS_HTTP_PORT}" ]]; then
  NAS_HTTP_PORT="$(prompt_port "DSM HTTP port" "5000")"
fi
if [[ -z "${NAS_HTTPS_PORT}" ]]; then
  NAS_HTTPS_PORT="$(prompt_port "DSM HTTPS port" "5001")"
fi
if [[ -z "${NAS_HTTP_PORT}" ]]; then NAS_HTTP_PORT="5000"; fi
if [[ -z "${NAS_HTTPS_PORT}" ]]; then NAS_HTTPS_PORT="5001"; fi

cat > "${LOCAL_TMP}/rokuvte-port-map.json" <<EOF
{
  "${NAS_HTTPS_PORT}": "${NAS_HTTP_PORT}"
}
EOF

cat > "${LOCAL_TMP}/rokuvte.cgi.b64" <<'EOF'
f0VMRgIBAQAAAAAAAAAAAAIAPgABAAAAeABAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAEAAOAABAAAAAAAAAAEAAAAFAAAAAAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAACAEAAAAAAAAIAQAAAAAAAAAQAAAAAAAASDHtSIscJEiNVNwQSI09IAAAAEiNNV4AAABIx8A7AAAADwVIx8d/AAAASMfAPAAAAA8FL3Vzci9iaW4vcHl0aG9uMwAvdXNyL3N5bm8vc3lub21hbi93ZWJhcGkvVmlkZW9TdGF0aW9uL3Jva3V2dGUucHkAAAAAqwBAAAAAAAC8AEAAAAAAAAAAAAAAAAAA
EOF

if base64 -d < "${LOCAL_TMP}/rokuvte.cgi.b64" > "${LOCAL_TMP}/rokuvte.cgi" 2>/dev/null; then
  :
else
  base64 -D -i "${LOCAL_TMP}/rokuvte.cgi.b64" -o "${LOCAL_TMP}/rokuvte.cgi"
fi
chmod 755 "${LOCAL_TMP}/rokuvte.cgi"

echo "Installing RokuVTE wrapper to ${SSH_TARGET}"
echo "Local wrapper: ${PY_WRAPPER}"
echo "Port map: HTTPS ${NAS_HTTPS_PORT} -> local HTTP ${NAS_HTTP_PORT}"
if [[ -n "${REMOTE_ELEVATE}" ]]; then
  echo "Remote elevation: ${REMOTE_ELEVATE}"
fi

ssh "${SSH_TARGET}" "rm -rf '${REMOTE_TMP}' && mkdir -p '${REMOTE_TMP}'"
ssh "${SSH_TARGET}" "cat > '${REMOTE_TMP}/rokuvte.cgi'" < "${LOCAL_TMP}/rokuvte.cgi"
ssh "${SSH_TARGET}" "cat > '${REMOTE_TMP}/rokuvte.py'" < "${PY_WRAPPER}"
ssh "${SSH_TARGET}" "cat > '${REMOTE_TMP}/rokuvte-port-map.json'" < "${LOCAL_TMP}/rokuvte-port-map.json"

if [[ -n "${REMOTE_ELEVATE}" ]]; then
  ssh -t "${SSH_TARGET}" "${REMOTE_ELEVATE} sh -s '${REMOTE_TMP}'" <<'REMOTE_SH'
set -euo pipefail

REMOTE_TMP="$1"
TARGET_DIR="/var/packages/VideoStation/target/ui/webapi"
GLOBAL_LINK="/usr/syno/synoman/webapi/VideoStation"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/rokuvte-wrapper-backup-${STAMP}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Video Station webapi directory not found: $TARGET_DIR" >&2
  exit 1
fi

if [ ! -e "$TARGET_DIR/movie.cgi" ]; then
  echo "Video Station webapi directory does not look right: missing movie.cgi" >&2
  exit 1
fi

if [ ! -x /usr/bin/python3 ]; then
  echo "Missing /usr/bin/python3 on NAS; wrapper needs Python 3." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
for name in rokuvte.cgi rokuvte.py rokuvte-port-map.json VideoStation.api; do
  if [ -e "$TARGET_DIR/$name" ]; then
    cp -p "$TARGET_DIR/$name" "$BACKUP_DIR/$name"
  fi
done

install -m 755 "$REMOTE_TMP/rokuvte.cgi" "$TARGET_DIR/rokuvte.cgi"
install -m 755 "$REMOTE_TMP/rokuvte.py" "$TARGET_DIR/rokuvte.py"
install -m 644 "$REMOTE_TMP/rokuvte-port-map.json" "$TARGET_DIR/rokuvte-port-map.json"
chown VideoStation:system "$TARGET_DIR/rokuvte.cgi" "$TARGET_DIR/rokuvte.py" "$TARGET_DIR/rokuvte-port-map.json"

if [ ! -e "$GLOBAL_LINK/rokuvte.cgi" ]; then
  echo "Warning: $GLOBAL_LINK/rokuvte.cgi is not visible. The global VideoStation webapi symlink may be missing." >&2
fi

rm -rf "$REMOTE_TMP"

echo "Installed:"
ls -l "$TARGET_DIR/rokuvte.cgi" "$TARGET_DIR/rokuvte.py" "$TARGET_DIR/rokuvte-port-map.json"
echo "Backup: $BACKUP_DIR"
REMOTE_SH
else
  ssh "${SSH_TARGET}" "sh -s '${REMOTE_TMP}'" <<'REMOTE_SH'
set -euo pipefail

REMOTE_TMP="$1"
TARGET_DIR="/var/packages/VideoStation/target/ui/webapi"
GLOBAL_LINK="/usr/syno/synoman/webapi/VideoStation"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/rokuvte-wrapper-backup-${STAMP}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Video Station webapi directory not found: $TARGET_DIR" >&2
  exit 1
fi

if [ ! -e "$TARGET_DIR/movie.cgi" ]; then
  echo "Video Station webapi directory does not look right: missing movie.cgi" >&2
  exit 1
fi

if [ ! -x /usr/bin/python3 ]; then
  echo "Missing /usr/bin/python3 on NAS; wrapper needs Python 3." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
for name in rokuvte.cgi rokuvte.py rokuvte-port-map.json VideoStation.api; do
  if [ -e "$TARGET_DIR/$name" ]; then
    cp -p "$TARGET_DIR/$name" "$BACKUP_DIR/$name"
  fi
done

install -m 755 "$REMOTE_TMP/rokuvte.cgi" "$TARGET_DIR/rokuvte.cgi"
install -m 755 "$REMOTE_TMP/rokuvte.py" "$TARGET_DIR/rokuvte.py"
install -m 644 "$REMOTE_TMP/rokuvte-port-map.json" "$TARGET_DIR/rokuvte-port-map.json"
chown VideoStation:system "$TARGET_DIR/rokuvte.cgi" "$TARGET_DIR/rokuvte.py" "$TARGET_DIR/rokuvte-port-map.json"

if [ ! -e "$GLOBAL_LINK/rokuvte.cgi" ]; then
  echo "Warning: $GLOBAL_LINK/rokuvte.cgi is not visible. The global VideoStation webapi symlink may be missing." >&2
fi

rm -rf "$REMOTE_TMP"

echo "Installed:"
ls -l "$TARGET_DIR/rokuvte.cgi" "$TARGET_DIR/rokuvte.py" "$TARGET_DIR/rokuvte-port-map.json"
echo "Backup: $BACKUP_DIR"
REMOTE_SH
fi

echo "Checking wrapper endpoint..."
if command -v curl >/dev/null 2>&1; then
  HOST="${SSH_TARGET#*@}"
  CHECK_BASE="${NAS_WEB_BASE:-http://${HOST}:5000}"
  CHECK_URL="${CHECK_BASE%/}/webapi/VideoStation/rokuvte.cgi"
  CHECK_BODY="$(curl -m 10 -fsS "${CHECK_URL}" || true)"
  WATCH_CHECK_BODY="$(curl -m 10 -fsS "${CHECK_URL}?action=watch_status" || true)"
  if [[ "${CHECK_BODY}" == "missing sid or file_id" ]]; then
    echo "OK: ${CHECK_URL} returned wrapper response."
  else
    echo "Warning: endpoint check did not return expected wrapper text."
    echo "URL: ${CHECK_URL}"
    echo "Response starts:"
    printf '%s\n' "${CHECK_BODY}" | head -5
  fi
  if [[ "${WATCH_CHECK_BODY}" == *'"error": "missing sid"'* || "${WATCH_CHECK_BODY}" == *'"error":"missing sid"'* ]]; then
    echo "OK: watch-status action returned wrapper response."
  else
    echo "Warning: watch-status action did not return expected wrapper JSON."
    echo "Response starts:"
    printf '%s\n' "${WATCH_CHECK_BODY}" | head -5
  fi
else
  echo "curl not found locally; skipping endpoint check."
fi

echo "Done."
