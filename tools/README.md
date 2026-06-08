# DS Video Restore Kit

This folder is a disaster-recovery kit for Synology Video Station, DS video,
Media Server, Advanced Media Extensions / CodecPack, and the RokuVTE wrapper
needed after DSM 7.2.2+ removed the supported Video Station path.

## Folder Layout

Keep the restore files together under one folder:

```text
/volume1/docker/DS Video/restore-kit
```

The script resolves everything relative to its own location, so it can be run
from any current working directory. The important files are:

```text
restore-kit/ds-video-restore-kit.sh
restore-kit/Video_Station_for_DSM_722-1.4.22/videostation_for_722.sh
restore-kit/rokuvte/videostation-rokuvte.cgi
restore-kit/packages
```

The `packages` folder is reference/fallback material. The tested restore flow
uses the saved 007revad script for the Synology packages, then installs the
patched RokuVTE wrapper.

## NAS `wget` Install

SSH into the NAS as root, then download the GitHub `main` branch:

```sh
mkdir -p "/volume1/docker/DS Video/restore-kit"
cd /tmp
wget -O ds-video-main.tar.gz "https://github.com/sapman1208/DS-Video-for-Roku-TV/archive/refs/heads/main.tar.gz"
tar -xzf ds-video-main.tar.gz
cp -R DS-Video-for-Roku-TV-main/tools/. "/volume1/docker/DS Video/restore-kit/"
chmod +x "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" "/volume1/docker/DS Video/restore-kit/build-ds-video-restore-kit.py"
```

Download the Synology SPKs for this NAS architecture:

```sh
cd "/volume1/docker/DS Video/restore-kit"
python3 build-ds-video-restore-kit.py --output "/volume1/docker/DS Video/ds-video-restore-kit-download" --arch auto --include-optional --no-archive
cp -R "/volume1/docker/DS Video/ds-video-restore-kit-download/restore-kit/packages" "/volume1/docker/DS Video/restore-kit/"
```

Run the restore:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --debug
```

After restore, open Package Center, open Advanced Media Extensions / CodecPack,
and sign in/install the codec entitlement before testing AVI, HEVC, AVC, or
other transcoded playback.

## Build A Downloadable Kit

From macOS, Linux, Windows, or a NAS with Python 3, build a fresh downloadable
restore kit from Synology's package archive:

```sh
python3 tools/build-ds-video-restore-kit.py --output ds-video-restore-kit-download --include-optional
```

If Python reports a local certificate verification error while downloading from
Synology's archive, rerun the same command with `--insecure`.

If you are already inside a copied `restore-kit` folder, run:

```sh
python3 build-ds-video-restore-kit.py --output ds-video-restore-kit-download --include-optional
```

To build a kit that includes every architecture Synology publishes for the
tested packages:

```sh
python3 tools/build-ds-video-restore-kit.py --output ds-video-restore-kit-all-arch --all-architectures --include-optional
```

The downloader writes:

```text
ds-video-restore-kit-download/restore-kit
ds-video-restore-kit-download/restore-kit/packages/<arch>
ds-video-restore-kit-download.zip
ds-video-restore-kit-download.tar.gz
```

Use `--arch auto` on a Synology NAS to detect the local package architecture, or
set an explicit list such as `--arch x86_64,armv8,rtd1296`.

## Tested Fresh VM Restore

Run this as root on the fresh NAS VM:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --debug
```

If DSM is using custom login ports, pass them on the same command:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --dsm-http-port=5000 --dsm-https-port=5001 --debug
```

If no port flags are typed, the script defaults to standard DSM ports:
HTTP `5000` and HTTPS `5001`.

That combined command runs the tested order:

1. `videostation_for_722.sh --install=all`
2. RokuVTE wrapper install
3. Package status and debugging diagnostics

Safety guard: if Video Station is already installed, the script skips the
007revad package-restore phase so it does not reinstall or downgrade an existing
Video Station package. It can still refresh the RokuVTE wrapper.

Only force the package restore when you intentionally want to reinstall the
Synology packages:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --force-722-install --debug
```

If you want to run the two install phases manually, use:

```sh
/bin/bash "/volume1/docker/DS Video/restore-kit/Video_Station_for_DSM_722-1.4.22/videostation_for_722.sh" --install=all
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --install-rokuvte --debug
```

## Preflight And Dry Run

Check required files without installing:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --preflight-only --debug
```

Show what would run:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --dry-run --debug
```

## RokuVTE Wrapper

The latest patched RokuVTE wrapper is included under:

```text
/volume1/docker/DS Video/restore-kit/rokuvte
```

Install or refresh only the Roku wrapper:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --install-rokuvte --debug
```

Use custom DSM ports if needed:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --install-rokuvte --rokuvte-http=5000 --rokuvte-https=5001 --debug
```

The equivalent DSM-style aliases are:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --install-rokuvte --dsm-http-port=5000 --dsm-https-port=5001 --debug
```

The installer writes:

```text
/var/packages/VideoStation/target/ui/webapi/rokuvte.cgi
/var/packages/VideoStation/target/ui/webapi/rokuvte.py
/var/packages/VideoStation/target/ui/webapi/rokuvte-port-map.json
```

It also backs up any existing RokuVTE files under `/root`.

## AME Note

After the packages install, open Advanced Media Extensions in Package Center and
sign in/install the codec entitlement if Video Station spins on AVI, HEVC, or
other transcoded playback. In VM testing, browser AVI playback worked after AME
was signed in.

## Optional Fallbacks

Run only the saved 007revad script:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --run-722-script --debug
```

This also respects the installed Video Station safeguard unless
`--force-722-install` is provided.

The local-SPK path is kept for reference and forensic testing only:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --local-spks --debug
```

For a multi-architecture kit, the script checks `packages/$SPK_ARCH` first.
Override detection when needed:

```sh
SPK_ARCH=rtd1296 /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --local-spks --debug
```

Do not use the old BSM-only CodecPack or DSM-version-limited Video Station SPKs
as the main recovery path. The known-good VM path used the 007revad script.

Optional wrapper patchers are preserved but not applied by default:

```sh
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --darknebular-wrapper --debug
/bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --alexpresso-wrapper --debug
```

## Debug Logs

Logs are written to the `LOG` path if provided. Otherwise the default is:

```text
/tmp/ds-video-restore-kit.log
```

For clean VM testing, prefer timestamped logs:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh "/volume1/docker/DS Video/restore-kit/ds-video-restore-kit.sh" --debug
```

The debug log captures DSM version, model, platform, mounts, disk space, backup
folder inventory, package status, Video Station webapi state, RokuVTE files, and
recent package-related log paths.

## Verification

After restore, verify:

```sh
synopkg status CodecPack
synopkg status VideoStation
synopkg status MediaServer
ls -l /var/packages/VideoStation/target/ui/webapi/rokuvte.*
```

Expected RokuVTE files:

```text
rokuvte.cgi
rokuvte.py
```

## Older SPKs And Live Backups

Older builds and other model architectures are preserved elsewhere under:

```text
/volume1/docker/DS Video/SPK Backups - Multi NAS
```

Use those only as reference material for package `INFO`, dependencies,
privileges, or install scripts.

The live package/config backup created on Hogwarts remains:

```text
/volume1/docker/DS Video/Apollo Lake - Latest SPKs/synology-video-transcoder-backup-20260608-062844/video-station-codecpack-files.tar.gz
```

Treat that archive as reference/restoration material after SPK/script installs,
not the first thing to overlay on a clean NAS.
