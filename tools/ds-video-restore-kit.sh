#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${BASE_DIR:-}" ]; then
  case "$(basename "$SCRIPT_DIR")" in
    restore-kit) BASE_DIR=$(dirname "$SCRIPT_DIR") ;;
    *) BASE_DIR="$SCRIPT_DIR" ;;
  esac
fi
APOLLO_DIR="${APOLLO_DIR:-$SCRIPT_DIR/packages}"
if [ ! -d "$APOLLO_DIR" ] && [ -d "$BASE_DIR/Apollo Lake - Latest SPKs" ]; then
  APOLLO_DIR="$BASE_DIR/Apollo Lake - Latest SPKs"
fi
SPK_ARCH="${SPK_ARCH:-}"
PACKAGE_DIR=""
REVAD_DIR="${REVAD_DIR:-$SCRIPT_DIR/Video_Station_for_DSM_722-1.4.22}"
if [ ! -d "$REVAD_DIR" ] && [ -d "$BASE_DIR/Video_Station_for_DSM_722-1.4.22" ]; then
  REVAD_DIR="$BASE_DIR/Video_Station_for_DSM_722-1.4.22"
fi
REVAD_SCRIPT="$REVAD_DIR/videostation_for_722.sh"
DARKNEBULAR_DIR="${DARKNEBULAR_DIR:-$SCRIPT_DIR/Wrapper_VideoStation-SCPT_3.9.9}"
if [ ! -d "$DARKNEBULAR_DIR" ] && [ -d "$BASE_DIR/Wrapper_VideoStation - darknebular/Wrapper_VideoStation-SCPT_3.9.9" ]; then
  DARKNEBULAR_DIR="$BASE_DIR/Wrapper_VideoStation - darknebular/Wrapper_VideoStation-SCPT_3.9.9"
fi
ALEXPRESSO_DIR="${ALEXPRESSO_DIR:-$SCRIPT_DIR/VideoStation-FFMPEG-Patcher-3.3}"
if [ ! -d "$ALEXPRESSO_DIR" ] && [ -d "$BASE_DIR/Video Station FFMPEG Patcher - AlexPresso/VideoStation-FFMPEG-Patcher-3.3" ]; then
  ALEXPRESSO_DIR="$BASE_DIR/Video Station FFMPEG Patcher - AlexPresso/VideoStation-FFMPEG-Patcher-3.3"
fi
LOG=${LOG:-/tmp/ds-video-restore-kit.log}
ROKUVTE_DIR="${ROKUVTE_DIR:-$SCRIPT_DIR/rokuvte}"
ROKUVTE_HTTP_PORT=${ROKUVTE_HTTP_PORT:-5000}
ROKUVTE_HTTPS_PORT=${ROKUVTE_HTTPS_PORT:-5001}

DRY_RUN=0
INSTALL_VS_307=0
RUN_REVAD=0
APPLY_DARKNEBULAR=0
APPLY_ALEXPRESSO=0
INSTALL_ROKUVTE=0
DEBUG=0
PREFLIGHT_ONLY=0
LOCAL_SPKS=0
FORCE_722_INSTALL=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Restores the saved DS Video / Video Station stack from:
  $SCRIPT_DIR

Options:
  --dry-run              Show what would run without changing packages.
  --local-spks           Legacy/manual local SPK path, not the default tested flow.
  --video-station-307    With --local-spks, install Video Station 3.0.7-2512 if present.
  --run-722-script       Run only the saved 007revad script.
  --force-722-install    Allow the 007revad script even if Video Station is installed.
  --darknebular-wrapper  Run the saved darknebular offline wrapper installer.
  --alexpresso-wrapper   Run the saved AlexPresso patcher with ffmpeg7.
  --install-rokuvte      Install only the latest saved Roku Video Station wrapper.
  --rokuvte-http=PORT    Local DSM HTTP port for RokuVTE. Default: 5000.
  --rokuvte-https=PORT   DSM HTTPS port mapped to HTTP. Default: 5001.
  --dsm-http-port=PORT   Alias for --rokuvte-http.
  --dsm-https-port=PORT  Alias for --rokuvte-https.
  --debug                Capture extra diagnostics and shell trace.
  --preflight-only       Check required backup files, then exit.
  -h, --help             Show this help.

Default behavior runs the tested flow:
  1. 007revad Video Station restore script --install=all
  2. RokuVTE wrapper install

Broken/version-limited local SPKs are not used by default.
Set SPK_ARCH to override local package architecture selection.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --local-spks) LOCAL_SPKS=1 ;;
    --video-station-307) INSTALL_VS_307=1 ;;
    --run-722-script) RUN_REVAD=1 ;;
    --force-722-install) FORCE_722_INSTALL=1 ;;
    --darknebular-wrapper) APPLY_DARKNEBULAR=1 ;;
    --alexpresso-wrapper) APPLY_ALEXPRESSO=1 ;;
    --install-rokuvte) INSTALL_ROKUVTE=1 ;;
    --rokuvte-http=*) ROKUVTE_HTTP_PORT=${1#*=} ;;
    --rokuvte-https=*) ROKUVTE_HTTPS_PORT=${1#*=} ;;
    --dsm-http-port=*) ROKUVTE_HTTP_PORT=${1#*=} ;;
    --dsm-https-port=*) ROKUVTE_HTTPS_PORT=${1#*=} ;;
    --debug) DEBUG=1 ;;
    --preflight-only) PREFLIGHT_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: run as root." >&2
  exit 1
fi

SYNOPKG="${SYNOPKG:-}"
if [ -z "$SYNOPKG" ]; then
  if command -v synopkg >/dev/null 2>&1; then
    SYNOPKG=$(command -v synopkg)
  elif [ -x /usr/syno/bin/synopkg ]; then
    SYNOPKG=/usr/syno/bin/synopkg
  else
    SYNOPKG=synopkg
  fi
fi

detect_spk_arch() {
  platform=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/synoinfo.conf platform_name 2>/dev/null || true)
  machine=$(uname -m 2>/dev/null || true)
  case "$machine" in
    x86_64|amd64) echo x86_64; return 0 ;;
    aarch64|arm64)
      if [ -n "$platform" ]; then echo "$platform"; else echo armv8; fi
      return 0
      ;;
  esac
  if [ -n "$platform" ]; then
    echo "$platform"
  elif [ -n "$machine" ]; then
    echo "$machine"
  else
    echo x86_64
  fi
}

if [ -z "$SPK_ARCH" ]; then
  SPK_ARCH=$(detect_spk_arch)
fi
if [ -d "$APOLLO_DIR/$SPK_ARCH" ]; then
  PACKAGE_DIR="$APOLLO_DIR/$SPK_ARCH"
else
  PACKAGE_DIR="$APOLLO_DIR"
fi

run() {
  echo "+ $*" | tee -a "$LOG"
  if [ "$DRY_RUN" = "0" ]; then
    "$@" 2>&1 | tee -a "$LOG"
  fi
}

run_synopkg_install() {
  spk="$1"
  echo "+ $SYNOPKG install $spk" | tee -a "$LOG"
  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi
  out=$("$SYNOPKG" install "$spk" 2>&1 || true)
  printf '%s\n' "$out" | tee -a "$LOG"
  if printf '%s\n' "$out" | grep -q '"success":false'; then
    echo "ERROR: synopkg install failed for $spk" | tee -a "$LOG"
    exit 1
  fi
}

log_section() {
  echo "" | tee -a "$LOG"
  echo "## $*" | tee -a "$LOG"
}

capture() {
  title="$1"
  shift
  log_section "$title"
  echo "+ $*" | tee -a "$LOG"
  "$@" 2>&1 | tee -a "$LOG" || true
}

is_installed() {
  "$SYNOPKG" status "$1" >/dev/null 2>&1
}

is_package_installed() {
  pkg="$1"
  status=$("$SYNOPKG" status "$pkg" 2>/dev/null || true)
  if printf '%s\n' "$status" | grep -q '"status":"non_installed"'; then
    return 1
  fi
  if printf '%s\n' "$status" | grep -q '"package":"'"$pkg"'"'; then
    return 0
  fi
  return 1
}

run_722_restore_if_safe() {
  if is_package_installed VideoStation && [ "$FORCE_722_INSTALL" = "0" ]; then
    echo "SKIP: Video Station is already installed; not running 007revad package restore." | tee -a "$LOG"
    echo "      Use --force-722-install only if you intentionally want to reinstall/downgrade packages." | tee -a "$LOG"
    return 0
  fi
  run /bin/bash "$REVAD_SCRIPT" --install=all
}

require_installed_after_install() {
  pkg="$1"
  if "$SYNOPKG" status "$pkg" 2>&1 | tee -a "$LOG" | grep -q '"status":"non_installed"'; then
    echo "ERROR: $pkg is still non-installed after synopkg install." | tee -a "$LOG"
    echo "Recent synopkg log:" | tee -a "$LOG"
    tail -n 120 /var/log/synopkg.log 2>&1 | tee -a "$LOG" || true
    echo "Recent synopkg manager log:" | tee -a "$LOG"
    tail -n 120 /var/log/synopkgmgr.log 2>&1 | tee -a "$LOG" || true
    exit 1
  fi
}

install_spk() {
  pkg="$1"
  spk="$2"
  log_section "Package candidate: $pkg"
  echo "SPK: $spk" | tee -a "$LOG"
  if [ -f "$spk" ]; then
    capture "SPK INFO if plain tar-readable: $pkg" tar -xOf "$spk" INFO
  fi
  if is_installed "$pkg"; then
    echo "SKIP: $pkg is already installed." | tee -a "$LOG"
    return 0
  fi
  if [ ! -f "$spk" ]; then
    echo "ERROR: missing SPK for $pkg: $spk" >&2
    exit 1
  fi
  run_synopkg_install "$spk"
  capture "Post-install status: $pkg" "$SYNOPKG" status "$pkg"
  if [ "$DRY_RUN" = "0" ]; then
    require_installed_after_install "$pkg"
  fi
}

find_one() {
  dir="$1"
  pattern="$2"
  found=$(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort | tail -n 1)
  if [ -z "$found" ]; then
    echo "ERROR: no file matching $pattern in $dir" >&2
    exit 1
  fi
  echo "$found"
}

find_preferred() {
  dir="$1"
  shift
  for pattern in "$@"; do
    if [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -name "$pattern" | grep -q .; then
      find_one "$dir" "$pattern"
      return 0
    fi
  done
  echo "ERROR: no preferred SPK found in $dir for: $*" >&2
  exit 1
}

require_path() {
  path="$1"
  if [ ! -e "$path" ]; then
    echo "MISSING: $path" | tee -a "$LOG"
    return 1
  fi
  echo "OK: $path" | tee -a "$LOG"
  return 0
}

preflight_required_files() {
  log_section "Required restore files"
  missing=0
  require_path "$SCRIPT_DIR/ds-video-restore-kit.sh" || missing=1
  require_path "$REVAD_SCRIPT" || missing=1
  require_path "$ROKUVTE_DIR/videostation-rokuvte.cgi" || missing=1
  if [ "$LOCAL_SPKS" = "1" ]; then
    require_path "$APOLLO_DIR" || missing=1
    echo "SPK architecture: $SPK_ARCH" | tee -a "$LOG"
    echo "SPK search dir: $PACKAGE_DIR" | tee -a "$LOG"
    for pattern in \
      'MediaServer-*.spk' \
      'CodecPack-*.spk' \
      'VideoStation-*.spk'
    do
      if [ -d "$PACKAGE_DIR" ] && find "$PACKAGE_DIR" -maxdepth 1 -type f -name "$pattern" | grep -q .; then
        echo "OK: $PACKAGE_DIR/$pattern" | tee -a "$LOG"
      else
        echo "MISSING: $PACKAGE_DIR/$pattern" | tee -a "$LOG"
        missing=1
      fi
    done
  fi
  if [ "$missing" = "1" ]; then
    cat <<EOF | tee -a "$LOG"

ERROR: required restore files are missing.

For the tested restore flow, keep these paths together:
  $SCRIPT_DIR/ds-video-restore-kit.sh
  $REVAD_SCRIPT
  $ROKUVTE_DIR/videostation-rokuvte.cgi

Local SPKs are optional reference/fallback material and are only checked with
--local-spks.
EOF
    exit 1
  fi
  if [ "$LOCAL_SPKS" = "1" ] && [ -f "$APOLLO_DIR/SHA256SUMS.txt" ]; then
    log_section "SPK checksums"
    oldpwd=$(pwd)
    cd "$APOLLO_DIR"
    if ! sha256sum -c SHA256SUMS.txt 2>&1 | tee -a "$LOG"; then
      cd "$oldpwd"
      echo "ERROR: one or more SPK checksums failed. Recopy the failed SPKs before installing." | tee -a "$LOG"
      exit 1
    fi
    cd "$oldpwd"
  elif [ "$LOCAL_SPKS" = "1" ] && [ -f "$PACKAGE_DIR/SHA256SUMS.txt" ]; then
    log_section "SPK checksums"
    oldpwd=$(pwd)
    cd "$PACKAGE_DIR"
    if ! sha256sum -c SHA256SUMS.txt 2>&1 | tee -a "$LOG"; then
      cd "$oldpwd"
      echo "ERROR: one or more SPK checksums failed. Recopy the failed SPKs before installing." | tee -a "$LOG"
      exit 1
    fi
    cd "$oldpwd"
  elif [ "$LOCAL_SPKS" = "1" ]; then
    echo "Warning: no checksum file found in $APOLLO_DIR or $PACKAGE_DIR; skipping checksum verification." | tee -a "$LOG"
  fi
}

install_rokuvte() {
  target_dir="/var/packages/VideoStation/target/ui/webapi"
  global_link="/usr/syno/synoman/webapi/VideoStation"
  py_wrapper="$ROKUVTE_DIR/videostation-rokuvte.cgi"
  installer="$ROKUVTE_DIR/install-videostation-rokuvte-wrapper.sh"
  tmp_dir="/tmp/rokuvte-restore-kit.$$"
  stamp=$(date +%Y%m%d-%H%M%S)
  backup_dir="/root/rokuvte-wrapper-backup-$stamp"

  if [ ! -d "$target_dir" ]; then
    echo "ERROR: Video Station webapi directory not found: $target_dir" >&2
    exit 1
  fi
  if [ ! -e "$target_dir/movie.cgi" ]; then
    echo "ERROR: Video Station webapi directory does not look right: missing movie.cgi" >&2
    exit 1
  fi
  if [ ! -x /usr/bin/python3 ]; then
    echo "ERROR: missing /usr/bin/python3; RokuVTE needs Python 3." >&2
    exit 1
  fi
  if [ ! -f "$py_wrapper" ]; then
    echo "ERROR: missing RokuVTE Python wrapper: $py_wrapper" >&2
    exit 1
  fi

  echo "Installing RokuVTE wrapper from $ROKUVTE_DIR" | tee -a "$LOG"
  [ -f "$installer" ] && echo "Saved host-side installer: $installer" | tee -a "$LOG"
  echo "RokuVTE port map: HTTPS $ROKUVTE_HTTPS_PORT -> local HTTP $ROKUVTE_HTTP_PORT" | tee -a "$LOG"

  if [ "$DRY_RUN" = "1" ]; then
    echo "+ install RokuVTE into $target_dir" | tee -a "$LOG"
    return 0
  fi

  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir" "$backup_dir"
  cat > "$tmp_dir/rokuvte.cgi.b64" <<'EOF'
f0VMRgIBAQAAAAAAAAAAAAIAPgABAAAAeABAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAEAAOAABAAAAAAAAAAEAAAAFAAAAAAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAACAEAAAAAAAAIAQAAAAAAAAAQAAAAAAAASDHtSIscJEiNVNwQSI09IAAAAEiNNV4AAABIx8A7AAAADwVIx8d/AAAASMfAPAAAAA8FL3Vzci9iaW4vcHl0aG9uMwAvdXNyL3N5bm8vc3lub21hbi93ZWJhcGkvVmlkZW9TdGF0aW9uL3Jva3V2dGUucHkAAAAAqwBAAAAAAAC8AEAAAAAAAAAAAAAAAAAA
EOF
  if base64 -d < "$tmp_dir/rokuvte.cgi.b64" > "$tmp_dir/rokuvte.cgi" 2>/dev/null; then
    :
  else
    base64 -D -i "$tmp_dir/rokuvte.cgi.b64" -o "$tmp_dir/rokuvte.cgi"
  fi
  chmod 755 "$tmp_dir/rokuvte.cgi"

  cat > "$tmp_dir/rokuvte-port-map.json" <<EOF
{
  "$ROKUVTE_HTTPS_PORT": "$ROKUVTE_HTTP_PORT"
}
EOF

  for name in rokuvte.cgi rokuvte.py rokuvte-port-map.json VideoStation.api; do
    if [ -e "$target_dir/$name" ]; then
      cp -p "$target_dir/$name" "$backup_dir/$name"
    fi
  done

  install -m 755 "$tmp_dir/rokuvte.cgi" "$target_dir/rokuvte.cgi"
  install -m 755 "$py_wrapper" "$target_dir/rokuvte.py"
  install -m 644 "$tmp_dir/rokuvte-port-map.json" "$target_dir/rokuvte-port-map.json"
  chown VideoStation:system "$target_dir/rokuvte.cgi" "$target_dir/rokuvte.py" "$target_dir/rokuvte-port-map.json"
  rm -rf "$tmp_dir"

  if [ ! -e "$global_link/rokuvte.cgi" ]; then
    echo "Warning: $global_link/rokuvte.cgi is not visible. The global VideoStation webapi symlink may be missing." | tee -a "$LOG"
  fi
  ls -l "$target_dir/rokuvte.cgi" "$target_dir/rokuvte.py" "$target_dir/rokuvte-port-map.json" | tee -a "$LOG"
  echo "RokuVTE backup: $backup_dir" | tee -a "$LOG"
}

echo "DS Video restore kit started $(date -Iseconds)" | tee "$LOG"
if [ "$DEBUG" = "1" ]; then
  set -x
fi
echo "Base: $BASE_DIR" | tee -a "$LOG"
echo "Host: $(hostname)" | tee -a "$LOG"
echo "DSM: $(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION productversion 2>/dev/null || true)-$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION buildnumber 2>/dev/null || true)" | tee -a "$LOG"
echo "Model: $(cat /proc/sys/kernel/syno_hw_version 2>/dev/null || true)" | tee -a "$LOG"
echo "Platform: $(/usr/syno/bin/synogetkeyvalue /etc.defaults/synoinfo.conf platform_name 2>/dev/null || true) $(uname -m)" | tee -a "$LOG"
echo "SPK arch: $SPK_ARCH" | tee -a "$LOG"
echo "Package dir: $PACKAGE_DIR" | tee -a "$LOG"
echo "synopkg: $SYNOPKG" | tee -a "$LOG"

log_section "Preflight"
capture "DSM VERSION" cat /etc.defaults/VERSION
capture "synoinfo platform" /usr/syno/bin/synogetkeyvalue /etc.defaults/synoinfo.conf platform_name
capture "kernel model" cat /proc/sys/kernel/syno_hw_version
capture "CPU" sh -c "sed -n '1,80p' /proc/cpuinfo"
capture "mounts" sh -c "mount | sed -n '1,120p'"
capture "disk space" df -h
capture "backup tree" sh -c "find '$BASE_DIR' -maxdepth 2 -type f -o -type d | sed -n '1,220p'"

if [ "$INSTALL_ROKUVTE" = "1" ] && [ "$RUN_REVAD" = "0" ] && [ "$APPLY_DARKNEBULAR" = "0" ] && [ "$APPLY_ALEXPRESSO" = "0" ]; then
  install_rokuvte
  echo "Done. Log: $LOG" | tee -a "$LOG"
  exit 0
fi

preflight_required_files
if [ "$PREFLIGHT_ONLY" = "1" ]; then
  echo "Preflight passed." | tee -a "$LOG"
  exit 0
fi

if [ "$RUN_REVAD" = "1" ] && [ "$LOCAL_SPKS" = "0" ] && [ "$INSTALL_ROKUVTE" = "0" ] && [ "$APPLY_DARKNEBULAR" = "0" ] && [ "$APPLY_ALEXPRESSO" = "0" ]; then
  log_section "Video Station restore"
  run_722_restore_if_safe
  echo "Done. Log: $LOG" | tee -a "$LOG"
  exit 0
fi

if [ "$LOCAL_SPKS" = "0" ]; then
  log_section "Video Station restore"
  run_722_restore_if_safe

  if [ "$APPLY_DARKNEBULAR" = "1" ]; then
    if [ ! -f "$DARKNEBULAR_DIR/installer_OffLine.sh" ]; then
      echo "ERROR: missing darknebular offline installer." >&2
      exit 1
    fi
    echo "Running darknebular offline installer. It may become interactive." | tee -a "$LOG"
    run /bin/bash "$DARKNEBULAR_DIR/installer_OffLine.sh"
  fi

  if [ "$APPLY_ALEXPRESSO" = "1" ]; then
    if [ ! -f "$ALEXPRESSO_DIR/patcher.sh" ]; then
      echo "ERROR: missing AlexPresso patcher." >&2
      exit 1
    fi
    run /bin/bash "$ALEXPRESSO_DIR/patcher.sh" -a patch -v 7
  fi

  install_rokuvte

  echo "Installed package status:" | tee -a "$LOG"
  for pkg in CodecPack VideoStation MediaServer; do
    "$SYNOPKG" status "$pkg" 2>&1 | tee -a "$LOG" || true
  done

  log_section "Final diagnostics"
  capture "Video Station webapi" sh -c "ls -l /var/packages/VideoStation/target/ui/webapi/rokuvte* 2>/dev/null"
  echo "Done. Log: $LOG" | tee -a "$LOG"
  exit 0
fi

log_section "Initial package status"
for pkg in synocli-videodriver ffmpeg7 Node.js_v22 MediaServer CodecPack VideoStation; do
  capture "Initial status: $pkg" "$SYNOPKG" status "$pkg"
done

if find "$PACKAGE_DIR" -maxdepth 1 -type f -name 'synocli-videodriver*.spk' | grep -q .; then
  install_spk synocli-videodriver "$(find_one "$PACKAGE_DIR" 'synocli-videodriver*.spk')"
else
  echo "SKIP: no synocli-videodriver SPK in $PACKAGE_DIR" | tee -a "$LOG"
fi
if find "$PACKAGE_DIR" -maxdepth 1 -type f -name 'ffmpeg7*.spk' | grep -q .; then
  install_spk ffmpeg7 "$(find_one "$PACKAGE_DIR" 'ffmpeg7*.spk')"
else
  echo "SKIP: no ffmpeg7 SPK in $PACKAGE_DIR" | tee -a "$LOG"
fi
if find "$PACKAGE_DIR" -maxdepth 1 -type f -name 'Node.js_v22-*.spk' | grep -q .; then
  install_spk Node.js_v22 "$(find_one "$PACKAGE_DIR" 'Node.js_v22-*.spk')"
else
  echo "SKIP: no Node.js_v22 SPK in $PACKAGE_DIR" | tee -a "$LOG"
fi
install_spk MediaServer "$(find_preferred "$PACKAGE_DIR" 'MediaServer-*-2.0.5-3152.spk' 'MediaServer-*.spk')"
if find "$PACKAGE_DIR" -maxdepth 1 -type f -name 'CodecPack-*.spk' | grep -q .; then
  install_spk CodecPack "$(find_preferred "$PACKAGE_DIR" 'CodecPack-*-3.1.0-3005.spk' 'CodecPack-*.spk')"
else
  install_spk CodecPack "$(find_one "$PACKAGE_DIR" 'CodecPack-BSM-*.spk')"
fi

if [ "$INSTALL_VS_307" = "1" ]; then
  install_spk VideoStation "$(find_one "$PACKAGE_DIR" 'VideoStation-*-3.0.7-2512.spk')"
else
  install_spk VideoStation "$(find_preferred "$PACKAGE_DIR" 'VideoStation-*-3.1.0-3153.spk' 'VideoStation-*.spk')"
fi

if [ "$RUN_REVAD" = "1" ]; then
  if [ ! -f "$REVAD_SCRIPT" ]; then
    echo "ERROR: missing 007revad script: $REVAD_SCRIPT" >&2
    exit 1
  fi
  run_722_restore_if_safe
fi

if [ "$APPLY_DARKNEBULAR" = "1" ]; then
  if [ ! -f "$DARKNEBULAR_DIR/installer_OffLine.sh" ]; then
    echo "ERROR: missing darknebular offline installer." >&2
    exit 1
  fi
  echo "Running darknebular offline installer. It may become interactive." | tee -a "$LOG"
  run /bin/bash "$DARKNEBULAR_DIR/installer_OffLine.sh"
fi

if [ "$APPLY_ALEXPRESSO" = "1" ]; then
  if [ ! -f "$ALEXPRESSO_DIR/patcher.sh" ]; then
    echo "ERROR: missing AlexPresso patcher." >&2
    exit 1
  fi
  run /bin/bash "$ALEXPRESSO_DIR/patcher.sh" -a patch -v 7
fi

if [ "$INSTALL_ROKUVTE" = "1" ]; then
  install_rokuvte
fi

echo "Installed package status:" | tee -a "$LOG"
for pkg in synocli-videodriver ffmpeg7 Node.js_v22 MediaServer CodecPack VideoStation; do
  "$SYNOPKG" status "$pkg" 2>&1 | tee -a "$LOG" || true
done

log_section "Final diagnostics"
capture "package directories" sh -c "for p in /var/packages/CodecPack /var/packages/VideoStation /var/packages/MediaServer /var/packages/ffmpeg7 /var/packages/synocli-videodriver /var/packages/Node.js_v22; do [ -e \"\$p\" ] && ls -ld \"\$p\" \"\$p/target\" 2>/dev/null || echo MISSING \"\$p\"; done"
capture "Video Station webapi" sh -c "ls -l /var/packages/VideoStation/target/ui/webapi 2>/dev/null | sed -n '1,120p'"
capture "CodecPack files" sh -c "find /var/packages/CodecPack/target -maxdepth 3 -type f 2>/dev/null | sed -n '1,160p'"
capture "recent package logs" sh -c "find /var/log -maxdepth 2 -type f \\( -iname '*synopkg*' -o -iname '*CodecPack*' -o -iname '*VideoStation*' -o -iname '*MediaServer*' \\) -print 2>/dev/null | sed -n '1,80p'"

echo "Done. Log: $LOG" | tee -a "$LOG"
