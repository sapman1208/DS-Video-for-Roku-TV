# Roku DS Video NAS Services

These scripts run the NAS-side helper services for the Roku channel.

## Modes

### On-Demand

Downloads missing subtitles on first start and as new files are indexed. Transcodes only when Roku plays an incompatible file.

```sh
cd /volume1/docker/roku-ds-video-tools
nas/start-on-demand.sh
```

Stop:

```sh
nas/stop-on-demand.sh
```

## Individual Services

Start only the playback/transcode proxy:

```sh
nas/start-hls-proxy.sh
```

Start only the subtitle watcher:

```sh
nas/start-subtitle-watcher.sh
```

## Manual Tools

The tools folder also includes maintenance scripts such as `normalize-media-plan.js`, `apply-normalize-plan.js`, `cleanup-normalize-leftovers.js`, `migrate-transcodes.js`, `generate-vsmeta.js`, and `generate-episode-posters.js`.

These are manual utilities. They are not run by `nas/start-on-demand.sh` or any individual service start script. Run them directly only after reviewing their dry-run output or script options.

## Environment

Scripts read `/volume1/docker/roku-ds-video-tools/.env`.

Useful settings:

```sh
OPEN_SUBTITLES_API_KEY=your-api-key
OPEN_SUBTITLES_LANGUAGE=en
SUBDL_API_KEY=your-subdl-api-key
ROKU_HLS_PORT=8099
ROKU_HLS_BASE_URL=https://your-hostname:8099
ROKU_HLS_SAVE_MP4=1
ROKU_HLS_REPLACE_ORIGINAL=1
ROKU_SUBTITLE_TVSUBTITLES=1
ROKU_SUBTITLE_POLL_SECONDS=900
```

`ROKU_HLS_SAVE_MP4=1` keeps completed on-demand transcodes under `/volume1/video/@roku-transcodes`. `ROKU_HLS_REPLACE_ORIGINAL=1` copies a completed MP4 back only after Roku playback has gone idle; interrupted or failed transcodes leave the original file untouched.

The subtitle watcher scans movie and TV-style library paths by default, such as `Movies` and `TV Shows`. Set `ROKU_SUBTITLE_INCLUDE_HOME=1` to include Home/Home Videos folders. Subtitles try SubDL first, then TVsubtitles.net for English TV episodes with cookie-based downloads and old-format normalization. Existing movie and episode `.srt` sidecars are normalized, commentary-trimmed when possible, and autosynced when `ffsubsync` is installed. Set `ROKU_SUBTITLE_TVSUBTITLES=0` to disable the TVsubtitles fallback. When OpenSubtitles quota is reached, the watcher logs `subtitle-quota-pause` and waits for the next poll.

## Logs

```text
/tmp/roku-hls-proxy.log
/tmp/roku-subtitle-watcher.log
```

## DSM Task Scheduler

Create a triggered task as root.

On-demand:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-on-demand.sh
```
