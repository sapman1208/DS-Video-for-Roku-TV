# Synology DS Video for Roku

A Roku channel for browsing and playing Synology Video Station libraries. The current build can use a small NAS-side Video Station wrapper so Roku can play Synology's own HLS/transcoded streams directly, including AVI files that Video Station can convert on the fly.

## Features

- Browse Movie, TV Show, Home Video, TV Recording, custom Video Station libraries, playlists, favorites, watch list, and shared videos.
- Show TV seasons, episode metadata, resume points, posters, episode thumbnails, and backdrops.
- Load artwork, metadata, playlists, watched state, ratings, and captions directly from Synology.
- Stream Roku-compatible MP4/M4V/MOV/MKV files directly when Roku can play them.
- Play Video Station HLS/transcoded streams directly through the NAS wrapper for formats such as AVI.
- Update watched status through Video Station during playback.
- Optionally convert incompatible files to MP4 on the NAS and write `.vsmeta` sidecars.
- Optionally download `.srt` subtitles for existing and newly indexed files.

## Requirements

- Synology DSM with Video Station installed and indexed.
- Roku device with Developer Mode enabled.
- A computer on the same network for sideloading the Roku channel.
- For direct Video Station HLS/AVI playback:
  - Video Station installed and working.
  - SSH access using a DSM administrator account that can use `sudo` to write Video Station package files.

## Roku Installation

Package this channel from the repository root:

```sh
zip -r /tmp/roku-ds-video.zip manifest source components images -x '*.DS_Store'
```

Open the Roku developer installer:

```text
http://ROKU_IP_ADDRESS/plugin_install
```

Upload `/tmp/roku-ds-video.zip`, install it, then launch the development channel.

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

- NAS address: hostname or IP only, such as `nas.example.com` or `10.0.1.80`.
- Port: your DSM port. Use `5001` for normal DSM HTTPS, or `5000` for DSM HTTP.
- Protocol: HTTP or HTTPS.
- Username and password: Synology account with Video Station access.

Credentials are saved on the Roku. Use `Settings` from the top navigation bar to edit them.

## NAS Wrapper Install

Install the NAS wrapper if you want AVI and other Video Station-transcoded files to play through Synology's own HLS stream.

Download the release asset named:

```text
roku-ds-video-nas-wrapper.zip
```

On macOS or Linux, unzip it, open Terminal, then run:

```sh
cd /path/to/roku-ds-video-nas-wrapper
chmod +x install-videostation-rokuvte-wrapper.sh
./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

Example:

```sh
./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

If you use HTTPS, or if your DSM web port is not the default `5000`, set `NAS_WEB_BASE` so the installer can verify the endpoint:

```sh
NAS_WEB_BASE=https://10.0.1.80:5001 ./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

On Windows, use WSL or Git Bash because the installer is a Bash script:

```sh
cd /mnt/c/Users/YOUR_NAME/Downloads/roku-ds-video-nas-wrapper
chmod +x install-videostation-rokuvte-wrapper.sh
./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

For HTTPS on Windows:

```sh
NAS_WEB_BASE=https://10.0.1.80:5001 ./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

The installer backs up any existing wrapper files under `/root/rokuvte-wrapper-backup-YYYYMMDD-HHMMSS` before installing:

```text
/var/packages/VideoStation/target/ui/webapi/rokuvte.cgi
/var/packages/VideoStation/target/ui/webapi/rokuvte.py
```

After install, the Roku app uses your normal DSM address, port, protocol, username, and password.

## Manual Maintenance Tools

The repository also includes helper scripts for one-off cleanup and media-library maintenance. These are not required for the Roku app or the Video Station wrapper.

Included manual tools:

- `normalize-media-plan.js`: previews media filename/folder normalization work.
- `apply-normalize-plan.js`: applies a previously reviewed normalization plan.
- `cleanup-normalize-leftovers.js`: removes leftover files from normalization work.
- `migrate-transcodes.js`: moves completed `@roku-transcodes` MP4s back into regular library folders.
- `generate-vsmeta.js`: writes `.vsmeta` sidecars when run directly.
- `generate-episode-posters.js`: generates episode poster images when run directly.

Run these manually only after reviewing their dry-run output or script options.

## FFmpeg and Node Paths

Some maintenance scripts check common Synology paths for FFmpeg and Node.js. When running those scripts manually, set `FFMPEG` or `NODE_BIN` if your packages use custom locations.

## Migrating Existing `@roku-transcodes` Files

If you already have completed MP4s in `/volume1/video/@roku-transcodes`, migrate them into regular library folders:

```sh
cd /volume1/docker/roku-ds-video-tools
/volume1/@appstore/homebridge/app/bin/node migrate-transcodes.js --dry-run
/volume1/@appstore/homebridge/app/bin/node migrate-transcodes.js --prune-root
```

## Troubleshooting

If playback fails:

- Confirm Video Station can play the file in the Synology web UI or DS video app.
- Re-run the NAS wrapper installer and confirm the endpoint check passes.
- Confirm the Roku app settings use the correct DSM address, port, protocol, username, and password.

If subtitles are missing:

- Confirm `.env` contains `SUBDL_API_KEY` and/or `OPEN_SUBTITLES_API_KEY`.
- Check `/tmp/roku-subtitle-watcher.log`.
- OpenSubtitles free/API quotas may pause downloads until the reset time in the log.
- Run `node subtitle-watcher.js --once --dry-run` to see what would be processed.

If conversion is not happening:

- Check `/tmp/roku-library-converter.log`.
- Confirm Video Station has indexed the file.
- Run `node library-converter.js --once --dry-run`.

If artwork is missing:

- Confirm the item has Video Station poster/backdrop metadata or a `.vsmeta` sidecar.
- Re-index Video Station metadata on the NAS.

## Development

Validate/build with BrightScript Compiler:

```sh
npx bsc --copy-to-staging=false
```

Package manually:

```sh
zip -r /tmp/roku-ds-video.zip manifest source components images -x '*.DS_Store'
```

Before publishing or sharing a build, update `build_version` in `manifest`.
