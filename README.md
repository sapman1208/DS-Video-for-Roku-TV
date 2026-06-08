# Synology DS Video for Roku

A Roku channel for browsing and playing Synology Video Station libraries, plus a
new DS Video restore kit for DSM builds where Synology removed Video Station,
DS video, and built-in transcoding support.

## What This Build Includes

- Roku channel source for Synology Video Station browsing and playback.
- Patched RokuVTE wrapper for Video Station streaming.
- Cross-platform restore-kit downloader for Synology SPKs.
- NAS-side restore script with safety guards so installed Video Station packages
  are not reinstalled or downgraded unless explicitly forced.

The old external NAS helper tools are no longer part of this build.

## Roku Installation

Package this channel from the repository root:

```sh
zip -r /tmp/roku-ds-video.zip manifest source components images -x '*.DS_Store'
```

Open the Roku developer installer:

```text
http://ROKU_IP_ADDRESS/plugin_install
```

Upload `/tmp/roku-ds-video.zip`, install it, then launch the development
channel.

You can also install with curl:

```sh
curl --digest -u rokudev:YOUR_ROKU_DEV_PASSWORD \
  -F 'mysubmit=Install' \
  -F 'archive=@/tmp/roku-ds-video.zip' \
  -F 'passwd=' \
  http://ROKU_IP_ADDRESS/plugin_install
```

## First App Login

On first launch, enter:

- NAS address: hostname or IP only, such as `nas.example.com` or `10.0.1.74`.
- Port: your DSM port. Use `5001` for normal DSM HTTPS, or `5000` for DSM HTTP.
- Protocol: HTTP or HTTPS.
- Username and password: Synology account with Video Station access.

Credentials are saved on the Roku. Use `Settings` from the top navigation bar to
edit them.

## Build A Restore Kit

The new restore-kit tooling lives in:

```text
tools/
```

## NAS `wget` Install

The easiest restore-kit install is from an SSH session on the NAS. This example
downloads the GitHub `main` branch and places the restore files in `/tmp`, so no
shared folder is required:

```sh
cd /tmp
wget -O ds-video-main.tar.gz "https://github.com/sapman1208/DS-Video-for-Roku-TV/archive/refs/heads/main.tar.gz"
tar -xzf ds-video-main.tar.gz
rm -rf /tmp/ds-video-restore-kit
mkdir -p /tmp/ds-video-restore-kit
cp -R DS-Video-for-Roku-TV-main/tools/. /tmp/ds-video-restore-kit/
chmod +x /tmp/ds-video-restore-kit/ds-video-restore-kit.sh /tmp/ds-video-restore-kit/build-ds-video-restore-kit.py
```

Then download the Synology SPKs into the restore-kit folder:

```sh
cd /tmp/ds-video-restore-kit
python3 build-ds-video-restore-kit.py --output /tmp/ds-video-restore-kit-download --arch auto --include-optional --no-archive
cp -R /tmp/ds-video-restore-kit-download/restore-kit/packages /tmp/ds-video-restore-kit/
```

Run the restore:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh /tmp/ds-video-restore-kit/ds-video-restore-kit.sh --debug
```

After restore, open Package Center, open Advanced Media Extensions / CodecPack,
and sign in/install the codec entitlement before testing AVI, HEVC, AVC, or
other transcoded playback.

`/tmp` is fine for a one-time install. Copy `/tmp/ds-video-restore-kit` to a
persistent shared folder afterward if you want to keep a local NAS backup.

From macOS, Linux, Windows, or a NAS with Python 3, build a downloadable restore
kit from Synology's package archive:

```sh
python3 tools/build-ds-video-restore-kit.py --output ds-video-restore-kit-download --include-optional
```

If Python reports a local certificate verification error while downloading from
Synology's archive, rerun the same command with `--insecure`.

Build every architecture Synology publishes for the tested packages:

```sh
python3 tools/build-ds-video-restore-kit.py --output ds-video-restore-kit-all-arch --all-architectures --include-optional
```

Build one explicit architecture:

```sh
python3 tools/build-ds-video-restore-kit.py --output ds-video-restore-kit-rtd1296 --arch rtd1296
```

The downloader writes:

```text
ds-video-restore-kit-download/restore-kit
ds-video-restore-kit-download/restore-kit/packages/<arch>
ds-video-restore-kit-download.zip
ds-video-restore-kit-download.tar.gz
```

Copy the generated `restore-kit` folder to the NAS. `/tmp/ds-video-restore-kit`
works for a one-time install:

```text
/tmp/ds-video-restore-kit
```

## Fresh NAS Restore

Run this as root on the NAS or VM:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh /tmp/ds-video-restore-kit/ds-video-restore-kit.sh --debug
```

If DSM uses custom login ports, pass them on the same command:

```sh
LOG="/tmp/ds-video-restore-kit-$(date +%Y%m%d-%H%M%S).log" /bin/sh /tmp/ds-video-restore-kit/ds-video-restore-kit.sh --dsm-http-port=5000 --dsm-https-port=5001 --debug
```

If no port flags are typed, the defaults are standard DSM ports: HTTP `5000`
and HTTPS `5001`.

The combined restore command runs:

1. Saved 007revad Video Station restore script.
2. Patched RokuVTE wrapper install.
3. Package status and debug diagnostics.

Safety guard: if Video Station is already installed, the script skips the
package-restore phase so it does not reinstall or downgrade your existing
package. To intentionally reinstall the Synology packages:

```sh
/bin/sh /tmp/ds-video-restore-kit/ds-video-restore-kit.sh --force-722-install --debug
```

## Codec Sign-In

After the restore, open Package Center and open Advanced Media Extensions /
CodecPack. Sign in with your Synology account and install/activate the codec
entitlement before testing AVI, HEVC, AVC, or other transcoded playback.

In VM testing, AVI browser playback spun until AME was signed in, then played
correctly.

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

## More Restore-Kit Details

See the detailed tool README:

```text
tools/README.md
```
