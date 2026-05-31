# Roku HLS Proxy on Synology NAS

This runs the FFmpeg HLS proxy on the NAS, so AVI/MKV transcoding does not use the Mac.

## Requirements

- Node.js installed on DSM.
- FFmpeg installed on DSM. The launcher checks common Synology package paths and also honors `FFMPEG=/path/to/ffmpeg`.
- Firewall allows Roku to reach TCP port `8099` on the NAS.

## Install

Copy the whole `tools` folder to the NAS. The expected layout is:

```sh
/volume1/docker/roku-ds-video-tools
/volume1/docker/roku-ds-video-tools/ffmpeg-hls-proxy.js
/volume1/docker/roku-ds-video-tools/nas/start-hls-proxy.sh
```

Start the proxy:

```sh
cd /volume1/docker/roku-ds-video-tools
chmod +x nas/start-hls-proxy.sh nas/stop-hls-proxy.sh
nas/start-hls-proxy.sh
```

Check it from another machine on the LAN:

```sh
curl http://NAS_HOST_OR_IP:8099/health
```

Expected response:

```json
{"ok":true,"sessions":0}
```

## DSM Task Scheduler

Create a triggered task that runs as root at boot:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-hls-proxy.sh
```

Stop it manually:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/stop-hls-proxy.sh
```

Logs default to:

```sh
/tmp/roku-hls-proxy.log
```

## HTTPS Reverse Proxy

For offsite Roku playback, put this proxy behind DSM Reverse Proxy or another HTTPS proxy.

Example:

- Source protocol: HTTPS
- Source hostname: your public hostname
- Source path: `/roku-hls`
- Destination protocol: HTTP
- Destination hostname: `127.0.0.1`
- Destination port: `8099`

Start the proxy with the same path prefix:

```sh
ROKU_HLS_PATH_PREFIX=/roku-hls nas/start-hls-proxy.sh
```

Then set the Roku app `Transcode URL` field to:

```text
https://your-public-hostname/roku-hls
```

If your reverse proxy does not pass `X-Forwarded-Proto` and `X-Forwarded-Host`, set `ROKU_HLS_BASE_URL` instead:

```sh
ROKU_HLS_BASE_URL=https://your-public-hostname/roku-hls ROKU_HLS_PATH_PREFIX=/roku-hls nas/start-hls-proxy.sh
```

## Native HTTPS on Port 8099

The proxy can also serve HTTPS directly if you point it at a certificate and key:

```sh
ROKU_HLS_PORT=8099 \
ROKU_HLS_HTTPS_CERT=/path/to/fullchain.pem \
ROKU_HLS_HTTPS_KEY=/path/to/privkey.pem \
ROKU_HLS_BASE_URL=https://your-public-hostname:8099 \
nas/start-hls-proxy.sh
```

Use this only if you can safely reference your Let's Encrypt certificate files from the start task.
