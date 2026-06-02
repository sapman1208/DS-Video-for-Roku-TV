# Roku DS Video Tools Synology Package

This project builds a DSM 7 `.spk` package for the NAS-side services used by the Roku DS Video channel.

The package installs:

- Roku HLS/MP4 proxy for files Roku cannot play directly.
- Subtitle downloader/watcher with SubDL and OpenSubtitles support.
- Optional background library converter for Roku-friendly MP4 files.
- VSMETA generation and migration utilities.
- DSM Package Center start/stop/status integration.

The package declares Synology `Node.js_v20` as an install dependency because the services are Node scripts. For transcoding, install either Video Station, SynoCommunity `ffmpeg7`, SynoCommunity `ffmpeg`, or set `FFMPEG=/path/to/ffmpeg` in the package config.

## Video Station

Video Station is Synology software and is not bundled in this repository. If Video Station disappears from Package Center, put an official Video Station `.spk` that you already have rights to use in:

```text
synology-spk/package/extras/VideoStation.spk
```

The Roku package will include it as an optional local installer asset. DSM 7 requires third-party packages to run as a package user instead of root, so the package cannot always install Video Station automatically. If the package log says it could not run `synopkg install`, install `VideoStation.spk` manually in Package Center first, then install or restart Roku DS Video Tools.

## ffmpeg wrapper

The package does not replace Video Station's ffmpeg wrapper automatically. The referenced `ffmpeg41-wrapper-DSM7_X-Advanced` project is a Video Station compatibility shim that routes difficult codecs through community ffmpeg. That is useful for Video Station itself, but the Roku app already uses its own ffmpeg path for on-the-fly transcodes and library conversion.

If you want the Video Station wrapper too, install it manually or add a vetted wrapper script under `package/extras/` and extend `package/tools/nas/install-videostation-wrapper.sh`. Do not install wrapper patches blindly because they modify files inside Synology packages.

## Build

From the repo root:

```sh
sh synology-spk/build-spk.sh
```

The output will be written to:

```text
synology-spk/out/RokuDSVideoTools-<version>.spk
```

Set a version explicitly:

```sh
VERSION=1.8.0 sh synology-spk/build-spk.sh
```

## Configure On NAS

After installation, edit the package config in DSM or over SSH:

```text
/var/packages/RokuDSVideoTools/var/config.env
```

Useful settings:

- `ROKU_SERVICE_MODE=on-demand` starts proxy and subtitle watcher.
- `ROKU_SERVICE_MODE=full` also starts the background library converter.
- `ROKU_HLS_PORT=8099` should match the Roku app.
- `ROKU_HLS_BASE_URL=https://your-hostname:8099` is used for subtitle/proxy URLs.
- Leave `ROKU_HLS_ROOT=` blank for the package-owned temp folder on a clean DSM install.
- Leave `ROKU_HLS_MP4_DIR=` blank until you grant the package user write access to a shared media folder.
- `SUBDL_API_KEY=` enables SubDL downloads.
- `OPEN_SUBTITLES_API_KEY=` enables OpenSubtitles downloads.

Restart the package after changing config.

Because DSM 7 runs this package as `RokuDSVideoTools`, grant that package user read access to your media folders and write access to any folders where it should save subtitles, VSMETA files, or converted MP4 files.

If Package Center says the service failed to start, check:

```text
/var/packages/RokuDSVideoTools/var/package-start.log
```
