# Synology DS Video for Roku v1.0.384 Draft

## Release Notes

This build uses a NAS-side Video Station wrapper for normal Video Station playback. AVI and other files that Video Station can transcode are requested through the wrapper and played by Roku as Synology HLS streams.

### What's New

- Direct Video Station HLS playback path for AVI/transcoded files.
- Broader TV episode fallback for shows whose Video Station title includes a year but the folder name does not.
- HLS resume no longer hides playback while Roku attempts an unreliable client-side seek.
- TV episode loading uses Synology episode records first, with safer folder fallback details when no playable records are returned.
- Transcoded HLS playback starts fresh instead of applying Roku-side resume state that can leave playback stuck at 0:00.
- HLS content now explicitly resets Roku play-start/bookmark fields to zero.
- NAS wrapper can clear Video Station's saved stream position before opening a wrapper HLS session.
- Watch-status updates through the Video Station wrapper.
- NAS wrapper waits briefly for Video Station to return a ready HLS playlist before Roku starts playback.
- Settings screen only asks for normal DSM connection details.
- Settings navigation fixes:
  - Settings opens with the Settings tab selected.
  - Down enters the credential fields.
  - OK edits the selected field.
  - Protocol OK toggles HTTP/HTTPS.
  - Save writes credentials and returns focus to the Settings tab.
- Regular login still saves credentials and lands in Movies.

### Release Assets

- `roku-ds-video.zip`: Roku development-channel zip.
- `roku-ds-video-nas-wrapper.zip`: NAS installer for the Video Station Roku wrapper.

### NAS Wrapper Install

Download `roku-ds-video-nas-wrapper.zip`.

On macOS or Linux, unzip it, open Terminal, then run:

```sh
cd /path/to/roku-ds-video-nas-wrapper
chmod +x install-videostation-rokuvte-wrapper.sh
./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

If you use HTTPS, pass the DSM web base URL used for the installer check:

```sh
NAS_WEB_BASE=https://10.0.1.80:5001 ./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

On Windows, use WSL or Git Bash because the installer is a Bash script:

```sh
cd /mnt/c/Users/YOUR_NAME/Downloads/roku-ds-video-nas-wrapper
chmod +x install-videostation-rokuvte-wrapper.sh
./install-videostation-rokuvte-wrapper.sh administrator@10.0.1.80
```

The installer backs up existing wrapper files under `/root/rokuvte-wrapper-backup-YYYYMMDD-HHMMSS`.

### Notes

- Video Station must be installed and indexed.
- The NAS wrapper requires SSH access with a DSM administrator account that can use `sudo` to install into Video Station's webapi folder.
