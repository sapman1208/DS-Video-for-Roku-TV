# Synology DS Video for Roku

A Roku channel for browsing and playing Synology Video Station libraries, with optional NAS-side helpers for Roku-friendly transcoding and subtitle downloads.

## Features

- Browse Movie, TV Show, Home Video, TV Recording, custom Video Station libraries, playlists, favorites, watch list, and shared videos.
- Show TV seasons, episode metadata, resume points, posters, episode thumbnails, and backdrops.
- Load artwork and captions directly from Synology when possible.
- Stream Roku-compatible MP4/M4V/MOV files directly.
- Transcode incompatible files through a NAS FFmpeg HLS service.
- Optionally convert incompatible files to MP4 on the NAS and write `.vsmeta` sidecars.
- Optionally download `.srt` subtitles for existing and newly indexed files.

## Requirements

- Synology DSM with Video Station installed and indexed.
- Roku device with Developer Mode enabled.
- A computer on the same network for sideloading the Roku channel.
- For NAS helper services:
  - Node.js on the NAS.
  - FFmpeg on the NAS.
  - TCP port `8099` reachable by the Roku, or an HTTPS reverse proxy.
  - Optional OpenSubtitles API settings for automatic subtitle downloads.

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

- NAS address: hostname or IP only, such as `nas.example.com` or `10.0.1.74`.
- Port: your DSM port. Use `5001` for normal DSM HTTPS, or `5000` for DSM HTTP.
- Protocol: HTTP or HTTPS.
- Username and password: Synology account with Video Station access.
- Transcode port: normally `8099`.

Credentials are saved on the Roku. Use `Settings` from the top navigation bar to edit them.

## NAS Tools Layout

Copy the whole `tools` folder to the NAS. The expected layout is:

```text
/volume1/docker/roku-ds-video-tools/
/volume1/docker/roku-ds-video-tools/ffmpeg-hls-proxy.js
/volume1/docker/roku-ds-video-tools/download-subtitles.js
/volume1/docker/roku-ds-video-tools/subtitle-watcher.js
/volume1/docker/roku-ds-video-tools/library-converter.js
/volume1/docker/roku-ds-video-tools/generate-vsmeta.js
/volume1/docker/roku-ds-video-tools/nas/start-hls-proxy.sh
/volume1/docker/roku-ds-video-tools/nas/start-on-demand.sh
/volume1/docker/roku-ds-video-tools/nas/start-full-automation.sh
```

The launcher scripts read `/volume1/docker/roku-ds-video-tools/.env` when present.

Example `.env` for subtitles and HTTPS:

```sh
OPEN_SUBTITLES_API_KEY=your-api-key
OPEN_SUBTITLES_LANGUAGE=en
ROKU_HLS_HTTPS_CERT=/path/to/fullchain.pem
ROKU_HLS_HTTPS_KEY=/path/to/privkey.pem
ROKU_HLS_BASE_URL=https://your-hostname:8099
```

## Build Modes

### On-Demand Mode

Use this mode when you want subtitles downloaded automatically, but videos converted only when Roku plays an incompatible file.

```sh
cd /volume1/docker/roku-ds-video-tools
chmod +x nas/*.sh
nas/start-on-demand.sh
```

Starts:

- `ffmpeg-hls-proxy.js`: transcodes only as needed during playback.
- `subtitle-watcher.js`: scans on first start, then polls for newly indexed files and downloads missing `.srt` files.

By default the subtitle watcher scans movie and TV-style library paths such as `Movies`, `New Stuff`, and `TV Shows`. Home videos are skipped by default to avoid false subtitle matches. Set `ROKU_SUBTITLE_INCLUDE_HOME=1` in `.env` if you want home-video folders included too. If OpenSubtitles reports a daily quota limit, the watcher logs `subtitle-quota-pause` and waits until the next poll.

Logs:

```text
/tmp/roku-hls-proxy.log
/tmp/roku-subtitle-watcher.log
```

Stop:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/stop-on-demand.sh
```

### Full Automation Mode

Use this mode when you want the NAS to keep the library Roku-ready in the background.

```sh
cd /volume1/docker/roku-ds-video-tools
chmod +x nas/*.sh
nas/start-full-automation.sh
```

Starts:

- `ffmpeg-hls-proxy.js`: on-demand playback fallback.
- `subtitle-watcher.js`: subtitles for existing and newly indexed files.
- `library-converter.js --watch --delete-original`: scans on first start, then polls for newly indexed incompatible videos, converts them to MP4, writes `.vsmeta`, indexes the replacement, and removes the original after the replacement succeeds. Compatible embedded text subtitle streams are written into the MP4 as `mov_text`, and matching sidecar `.srt`/`.vtt` files are copied to the new MP4 basename.

Logs:

```text
/tmp/roku-hls-proxy.log
/tmp/roku-subtitle-watcher.log
/tmp/roku-library-converter.log
```

Stop:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/stop-full-automation.sh
```

Preview conversion without changing files:

```sh
cd /volume1/docker/roku-ds-video-tools
/volume1/@appstore/homebridge/app/bin/node library-converter.js --once --dry-run
```

Run subtitle scan once without changing files:

```sh
cd /volume1/docker/roku-ds-video-tools
/volume1/@appstore/homebridge/app/bin/node subtitle-watcher.js --once --dry-run
```

## Manual Maintenance Tools

The NAS tools package also includes helper scripts for one-off cleanup and media-library maintenance. These are not run by `nas/start-on-demand.sh`, `nas/start-full-automation.sh`, or any other auto-start script.

Included manual tools:

- `normalize-media-plan.js`: previews media filename/folder normalization work.
- `apply-normalize-plan.js`: applies a previously reviewed normalization plan.
- `cleanup-normalize-leftovers.js`: removes leftover files from normalization work.
- `migrate-transcodes.js`: moves completed `@roku-transcodes` MP4s back into regular library folders.
- `generate-vsmeta.js`: writes `.vsmeta` sidecars when run directly.
- `generate-episode-posters.js`: generates episode poster images when run directly.

Run these manually only after reviewing their dry-run output or script options.

## DSM Task Scheduler

For on-demand mode at boot, create a triggered task as root:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-on-demand.sh
```

For full automation at boot:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-full-automation.sh
```

## Proxy Health

Check the HLS/transcode service:

```sh
curl http://NAS_IP_OR_HOSTNAME:8099/health
```

Expected:

```json
{"ok":true,"sessions":0}
```

## HTTPS Proxy Mode

The proxy can serve HTTPS directly:

```sh
ROKU_HLS_PORT=8099 \
ROKU_HLS_HTTPS_CERT=/path/to/fullchain.pem \
ROKU_HLS_HTTPS_KEY=/path/to/privkey.pem \
ROKU_HLS_BASE_URL=https://your-hostname.example.com:8099 \
nas/start-hls-proxy.sh
```

If you use DSM Reverse Proxy instead, point it to `127.0.0.1:8099` and set:

```sh
ROKU_HLS_BASE_URL=https://your-hostname.example.com/roku-hls \
ROKU_HLS_PATH_PREFIX=/roku-hls \
nas/start-hls-proxy.sh
```

## FFmpeg and Node Paths

The NAS scripts check common Synology paths for FFmpeg and Node.js. You can override paths:

```sh
FFMPEG=/path/to/ffmpeg NODE_BIN=/path/to/node nas/start-hls-proxy.sh
```

## Migrating Existing `@roku-transcodes` Files

If you already have completed MP4s in `/volume1/video/@roku-transcodes`, migrate them into regular library folders:

```sh
cd /volume1/docker/roku-ds-video-tools
/volume1/@appstore/homebridge/app/bin/node migrate-transcodes.js --dry-run
/volume1/@appstore/homebridge/app/bin/node migrate-transcodes.js --prune-root
```

## Troubleshooting

If playback fails:

- Confirm the proxy is running: `curl http://NAS_IP:8099/health`.
- Confirm Roku can reach the NAS/proxy port.
- Check `/tmp/roku-hls-proxy.log`.

If subtitles are missing:

- Confirm `.env` contains `OPEN_SUBTITLES_API_KEY`.
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
