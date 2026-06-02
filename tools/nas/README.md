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

### Full Automation

Downloads missing subtitles and converts incompatible videos in the background. The converter scans on first start, then polls for newly indexed files.

```sh
cd /volume1/docker/roku-ds-video-tools
nas/start-full-automation.sh
```

Stop:

```sh
nas/stop-full-automation.sh
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

Start only the background converter:

```sh
nas/start-library-converter.sh
```

## Manual Tools

The tools folder also includes maintenance scripts such as `normalize-media-plan.js`, `apply-normalize-plan.js`, `cleanup-normalize-leftovers.js`, `migrate-transcodes.js`, `generate-vsmeta.js`, and `generate-episode-posters.js`.

These are manual utilities. They are not run by `nas/start-on-demand.sh`, `nas/start-full-automation.sh`, or any individual service start script. Run them directly only after reviewing their dry-run output or script options.

## Environment

Scripts read `/volume1/docker/roku-ds-video-tools/.env`.

Useful settings:

```sh
OPEN_SUBTITLES_API_KEY=your-api-key
OPEN_SUBTITLES_LANGUAGE=en
ROKU_HLS_PORT=8099
ROKU_HLS_BASE_URL=https://your-hostname:8099
ROKU_SUBTITLE_POLL_SECONDS=900
ROKU_CONVERT_POLL_SECONDS=900
```

The subtitle watcher scans movie and TV libraries by default: `Movies`, `New Stuff`, `TV Shows`, and `Ian's Shows` (also matched as `Ians Shows`). Set `ROKU_SUBTITLE_INCLUDE_HOME=1` to include Home/Home Videos folders. When OpenSubtitles quota is reached, the watcher logs `subtitle-quota-pause` and waits for the next poll.

## Logs

```text
/tmp/roku-hls-proxy.log
/tmp/roku-subtitle-watcher.log
/tmp/roku-library-converter.log
```

## DSM Task Scheduler

Create a triggered task as root.

On-demand:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-on-demand.sh
```

Full automation:

```sh
cd /volume1/docker/roku-ds-video-tools && nas/start-full-automation.sh
```
