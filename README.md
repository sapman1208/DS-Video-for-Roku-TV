# Synology DS Video for Roku

A Roku channel for browsing and playing videos from Synology Video Station. It supports Movie, TV Show, Home Video, TV Recording, custom Video Station libraries, playlists, favorites/watch list/shared videos, metadata artwork, Roku-side artwork caching, and optional NAS-side FFmpeg transcoding for files Roku cannot play directly.

## Features

- Browse Synology Video Station libraries from Roku.
- Movie, TV show, episode, home video, TV recording, playlist, favorites, watch list, and shared-video views.
- TV seasons and episode metadata from Video Station.
- Posters, episode thumbnails, and backdrops.
- Roku device artwork cache using `cachefs:/`.
- Optional HTTPS FFmpeg HLS proxy for AVI/MKV/transcode-needed videos.
- Direct playback for Roku-compatible files when possible.

## Requirements

- Synology DSM with Video Station installed and indexed.
- Roku device with Developer Mode enabled.
- A computer on the same network for sideloading the Roku channel.
- For transcoding:
  - Node.js on the NAS.
  - FFmpeg on the NAS.
  - TCP port `8099` reachable by the Roku, or an HTTPS reverse proxy.

## Roku Installation

Enable Developer Mode on the Roku, then package this channel from the repository root:

```sh
zip -r /tmp/roku-ds-video.zip manifest source components images -x '*.DS_Store'
```

Open the Roku developer installer in a browser:

```text
http://ROKU_IP_ADDRESS/plugin_install
```

Upload `/tmp/roku-ds-video.zip`, install it, then launch the development channel from the Roku home screen.

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

- NAS address: hostname or IP only, such as `nas.example.com` or `10.0.1.1`.
- Port: your DSM Video Station port, such as `5000`, `5001`, or a custom port.
- Protocol: HTTP or HTTPS.
- Username and password: Synology account with Video Station access.
- Transcode port: normally `8099`.

Credentials are saved on the Roku. After that, the app auto logs in. Use `Settings` from the top navigation bar to edit them.

## NAS FFmpeg Proxy

The proxy is needed for files that Roku cannot play directly, such as many AVI and MKV files. It also exposes Video Station database artwork and metadata endpoints used by the Roku app.

Copy the `tools` folder to the NAS. Recommended layout:

```text
/volume1/docker/roku-ds-video-tools/
/volume1/docker/roku-ds-video-tools/ffmpeg-hls-proxy.js
/volume1/docker/roku-ds-video-tools/nas/start-hls-proxy.sh
/volume1/docker/roku-ds-video-tools/nas/stop-hls-proxy.sh
```

SSH into the NAS and start it:

```sh
cd /volume1/docker/roku-ds-video-tools
chmod +x nas/start-hls-proxy.sh nas/stop-hls-proxy.sh
nas/start-hls-proxy.sh
```

Check from another machine:

```sh
curl http://NAS_IP_OR_HOSTNAME:8099/health
```

Expected:

```json
{"ok":true,"sessions":0}
```

Stop it:

```sh
cd /volume1/docker/roku-ds-video-tools
nas/stop-hls-proxy.sh
```

Logs are written to:

```text
/tmp/roku-hls-proxy.log
```

## Start Proxy at Boot

In DSM Task Scheduler, create a triggered task that runs as `root` at boot:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-hls-proxy.sh
```

## HTTPS Proxy Mode

For offsite use, Roku should connect to an HTTPS endpoint with a trusted certificate.

The proxy can serve HTTPS directly:

```sh
ROKU_HLS_PORT=8099 \
ROKU_HLS_HTTPS_CERT=/path/to/fullchain.pem \
ROKU_HLS_HTTPS_KEY=/path/to/privkey.pem \
ROKU_HLS_BASE_URL=https://your-hostname.example.com:8099 \
nas/start-hls-proxy.sh
```

If you use DSM Reverse Proxy instead, point the reverse proxy to `127.0.0.1:8099` and set:

```sh
ROKU_HLS_BASE_URL=https://your-hostname.example.com/roku-hls \
ROKU_HLS_PATH_PREFIX=/roku-hls \
nas/start-hls-proxy.sh
```

Then use `your-hostname.example.com` and transcode port/path settings that match your public endpoint.

## FFmpeg and Node Paths

The NAS start script checks common Synology locations:

- `/var/packages/ffmpeg7/target/bin/ffmpeg`
- `/var/packages/ffmpeg/target/bin/ffmpeg`
- `ffmpeg` in `PATH`
- Node.js in `PATH`
- Synology Node.js package paths

You can override paths:

```sh
FFMPEG=/path/to/ffmpeg NODE_BIN=/path/to/node nas/start-hls-proxy.sh
```

## Artwork Cache

The Roku app stores downloaded posters and backdrops in Roku cache storage:

```text
cachefs:/ds_video_image_cache
```

On launch, the app starts a background pre-cache job that walks Video Station libraries and stores missing artwork. The first launch can be busier while the cache warms. Later launches should reuse cached images unless Roku clears cache storage.

## Troubleshooting

If playback fails:

- Confirm the NAS proxy is running: `curl http://NAS_IP:8099/health`.
- Confirm the Roku can reach the NAS/proxy port.
- For HTTPS, confirm the certificate is trusted and the hostname matches.
- Check `/tmp/roku-hls-proxy.log` on the NAS.
- Try an MP4 file first to confirm direct playback works.

If artwork is missing:

- Leave the app open for a few minutes after first launch so the cache can warm.
- Confirm the NAS proxy can read Video Station metadata.
- Check the proxy log for poster/backdrop errors.

If a library is missing or duplicated:

- Confirm the library is public/visible in Video Station.
- Re-index Video Station metadata on the NAS.
- Restart the NAS proxy after Video Station database changes.

## Development

The channel source is standard Roku SceneGraph/BrightScript:

```text
manifest
source/
components/
images/
tools/
```

Validate/build with BrightScript Compiler if available:

```sh
npx bsc --copy-to-staging=false
```

Package manually:

```sh
zip -r /tmp/roku-ds-video.zip manifest source components images -x '*.DS_Store'
```

Before publishing or sharing a build, update `build_version` in `manifest`.

