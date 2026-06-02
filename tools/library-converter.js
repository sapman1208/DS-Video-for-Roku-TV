#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const FFMPEG = process.env.FFMPEG || "/var/packages/ffmpeg7/target/bin/ffmpeg";
const FFPROBE = process.env.FFPROBE || FFMPEG.replace(/ffmpeg(?:\.exe)?$/i, "ffprobe");
const NODE_BIN = process.env.ROKU_HLS_NODE || process.execPath;
const VSMETA_GENERATOR = process.env.ROKU_HLS_VSMETA_GENERATOR || path.join(__dirname, "generate-vsmeta.js");
const SUBTITLE_DOWNLOADER = process.env.ROKU_HLS_SUBTITLE_DOWNLOADER || path.join(__dirname, "download-subtitles.js");
const POLL_SECONDS = Number(process.env.ROKU_CONVERT_POLL_SECONDS || 900);
const LIMIT = Number((process.argv.find((arg) => arg.startsWith("--limit=")) || "").split("=")[1] || 0);
const DRY_RUN = process.argv.includes("--dry-run");
const ONCE = process.argv.includes("--once") || !process.argv.includes("--watch");
const WATCH = process.argv.includes("--watch");
const DELETE_ORIGINAL = process.argv.includes("--delete-original") || process.env.ROKU_CONVERT_DELETE_ORIGINAL === "1";
const LOCK_FILE = process.env.ROKU_CONVERT_LOCK || "/tmp/roku-library-converter.lock";
const DIRECT_EXTENSIONS = new Set([".mp4", ".m4v", ".mov"]);
const VIDEO_EXTENSIONS = new Set([".avi", ".mkv", ".webm", ".m2ts", ".wmv", ".mpg", ".mpeg", ".ts", ".m2v", ".flv"]);
const TEXT_SUBTITLE_CODECS = new Set(["subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text"]);

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runSql(sql) {
  const command = `psql -U VideoStation -d video_metadata -X -q -t -A -F "\t" -c "${sql.replace(/"/g, '\\"')}"`;
  const result = spawnSync("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
    encoding: "utf8",
  });
  if (result.status !== 0) throw new Error((result.stderr || result.stdout || `psql failed ${result.status}`).trim());
  return String(result.stdout || "").trim();
}

function cleanNamePart(value) {
  return String(value || "")
    .replace(/[\\/:*?"<>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function withoutVideoExtension(value) {
  return String(value || "").replace(/\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|m2v|flv|webm)$/i, "");
}

function normalizeForCompare(value) {
  return cleanNamePart(withoutVideoExtension(value))
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function libraryNameForPart(part) {
  const norm = normalizeForCompare(part);
  if (norm === "tv shows") return "TV Shows";
  if (norm === "ians shows") return "Ian's Shows";
  if (norm === "movies" || norm === "movie") return "Movies";
  if (norm === "new stuff") return "New Stuff";
  if (norm === "home videos" || norm === "home video") return "Home Videos";
  if (norm === "tv recordings" || norm === "tv recording") return "TV Recordings";
  return "";
}

function stripReleaseTail(value) {
  let name = String(value || "");
  name = name.replace(/\[[^\]]+\]$/g, "");
  name = name.replace(/\([^)]*(rarbg|yts|eztv|ettv|tgx|torrent|xvid|x264|x265|web|hdtv|bdrip|bluray)[^)]*\)$/i, "");
  name = name.replace(/\b(2160p|1080p|720p|576p|540p|480p|360p)\b.*$/i, "");
  name = name.replace(/\b(uhd|hdr|web[-_. ]?dl|webrip|web|hdtv|bdrip|brrip|bluray|dvdrip|xvid|x264|x265|h264|h265|hevc|aac[0-9.]*|ac3|dts)\b.*$/i, "");
  name = name.replace(/[-_. ]+(proper|repack|internal)$/i, "");
  name = name.replace(/[-_. ]+[A-Za-z0-9]+$/i, (match) => {
    const part = match.replace(/^[-_. ]+/, "");
    return part.length <= 12 && /[A-Z]/.test(part) && /[a-z]/.test(part) === false ? "" : match;
  });
  return cleanNamePart(name);
}

function movieTitleFromFileName(fileName) {
  const baseName = withoutVideoExtension(fileName).replace(/[._]+/g, " ");
  const existingYear = baseName.match(/\((19\d{2}|20\d{2})\)/);
  if (existingYear) return cleanNamePart(baseName);
  const yearMatch = baseName.match(/\b(19\d{2}|20\d{2})\b/);
  if (!yearMatch) return stripReleaseTail(baseName);
  const year = yearMatch[1];
  const title = cleanNamePart(baseName.slice(0, yearMatch.index).replace(/[.\-_]+/g, " "));
  if (!title) return stripReleaseTail(baseName);
  return `${title} (${year})`;
}

function episodeInfoFromPath(filePath) {
  const parts = String(filePath || "").replace(/\\/g, "/").split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => {
    const library = libraryNameForPart(part);
    return library === "TV Shows" || library === "Ian's Shows";
  });
  if (libraryIndex < 0 || parts.length <= libraryIndex + 2) return null;
  const library = libraryNameForPart(parts[libraryIndex]);
  const show = cleanNamePart(parts[libraryIndex + 1]);
  const fileName = parts[parts.length - 1] || "";
  const baseName = withoutVideoExtension(fileName).replace(/[._]+/g, " ");
  const episodeMatch = baseName.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || baseName.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  const seasonFolder = parts.slice(libraryIndex + 2, -1).find((part) => /^season\s+\d+/i.test(part));
  const seasonFromFolder = seasonFolder ? Number((seasonFolder.match(/\d+/) || ["0"])[0]) : 0;
  if (!episodeMatch && !seasonFromFolder) return null;
  const season = episodeMatch ? Number(episodeMatch[1]) : seasonFromFolder;
  const episode = episodeMatch ? Number(episodeMatch[2]) : 0;
  if (!season || !episode) return null;
  let fileShow = "";
  if (episodeMatch && episodeMatch.index > 0) fileShow = cleanNamePart(baseName.slice(0, episodeMatch.index).replace(/[._-]+/g, " "));
  const outputShow = fileShow && normalizeForCompare(fileShow).length >= normalizeForCompare(show).length ? fileShow : show;
  let title = baseName;
  const showNorm = normalizeForCompare(outputShow);
  const titleNorm = normalizeForCompare(title);
  if (showNorm && titleNorm.startsWith(showNorm + " ")) title = title.slice(outputShow.length).trim();
  title = title.replace(/\bS\d{1,2}E\d{1,3}\b/i, " ");
  title = stripReleaseTail(title.replace(/[._]+/g, " ").replace(/^[-\s]+|[-\s]+$/g, ""));
  return { library, show: outputShow, season, episode, title };
}

function movieInfoFromPath(filePath) {
  const parts = String(filePath || "").replace(/\\/g, "/").split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => {
    const library = libraryNameForPart(part);
    return library === "Movies" || library === "New Stuff";
  });
  if (libraryIndex < 0 || parts.length <= libraryIndex + 1) return null;
  const title = movieTitleFromFileName(parts[parts.length - 1] || "");
  if (!title) return null;
  return { library: libraryNameForPart(parts[libraryIndex]), title };
}

function homeVideoInfoFromPath(filePath) {
  const parts = String(filePath || "").replace(/\\/g, "/").split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => libraryNameForPart(part) === "Home Videos");
  if (libraryIndex < 0 || parts.length <= libraryIndex + 1) return null;
  const title = cleanNamePart(withoutVideoExtension(parts[parts.length - 1] || "").replace(/[._]+/g, " "));
  if (!title) return null;
  return { library: "Home Videos", folders: parts.slice(libraryIndex + 1, -1).map(cleanNamePart).filter(Boolean), title };
}

function libraryRootForSource(sourcePath, libraryName) {
  const cleanPath = String(sourcePath || "").replace(/\\/g, "/");
  const needle = `/${libraryName}/`;
  const idx = cleanPath.toLowerCase().indexOf(needle.toLowerCase());
  if (idx < 0) return "";
  return cleanPath.slice(0, idx + libraryName.length + 1);
}

function targetPathForSource(sourcePath) {
  const episode = episodeInfoFromPath(sourcePath);
  if (episode) {
    const root = libraryRootForSource(sourcePath, episode.library);
    if (!root) return "";
    const season = String(episode.season).padStart(2, "0");
    const ep = String(episode.episode).padStart(2, "0");
    const titlePart = episode.title ? ` - ${cleanNamePart(episode.title)}` : "";
    return path.join(root, episode.show, `Season ${season}`, `${episode.show} - S${season}E${ep}${titlePart}.mp4`);
  }
  const movie = movieInfoFromPath(sourcePath);
  if (movie) {
    const root = libraryRootForSource(sourcePath, movie.library);
    if (!root) return "";
    const title = cleanNamePart(movie.title);
    return path.join(root, title, `${title}.mp4`);
  }
  const home = homeVideoInfoFromPath(sourcePath);
  if (home) {
    const root = libraryRootForSource(sourcePath, home.library);
    if (!root) return "";
    return path.join(root, ...home.folders, `${cleanNamePart(home.title)}.mp4`);
  }
  return "";
}

function transcodeNeeded(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return VIDEO_EXTENSIONS.has(ext) && !DIRECT_EXTENSIONS.has(ext);
}

function discoverCandidates() {
  const max = LIMIT > 0 ? `limit ${LIMIT}` : "";
  const rows = runSql(`
    select vf.path
    from video_file vf
    where vf.path is not null
      and lower(vf.path) ~ '\\.(avi|mkv|webm|m2ts|wmv|mpg|mpeg|ts|m2v|flv)$'
    order by vf.path
    ${max}`);
  if (!rows) return [];
  return rows.split("\n").map((line) => line.trim()).filter(Boolean).filter(transcodeNeeded);
}

function generateVsmeta(source, target) {
  if (!fs.existsSync(VSMETA_GENERATOR)) return false;
  const result = spawnSync(NODE_BIN, [VSMETA_GENERATOR, "--force", source, target], {
    encoding: "utf8",
    timeout: 120000,
  });
  if (result.status !== 0) {
    console.log(`[convert] vsmeta failed ${target}: ${(result.stderr || result.stdout || "").trim()}`);
    return false;
  }
  return fs.existsSync(`${target}.vsmeta`);
}

function indexReplacement(source, target) {
  const indexer = "/usr/syno/bin/synoindex";
  if (!fs.existsSync(indexer)) return;
  spawnSync(indexer, ["-d", source], { timeout: 30000 });
  spawnSync(indexer, ["-a", target], { timeout: 30000 });
}

function downloadSubtitles(target) {
  if (!process.env.SUBDL_API_KEY && !process.env.OPEN_SUBTITLES_API_KEY && !process.env.OPENSUBTITLES_API_KEY) return false;
  if (!fs.existsSync(SUBTITLE_DOWNLOADER)) return;
  const result = spawnSync(NODE_BIN, [SUBTITLE_DOWNLOADER, target], {
    encoding: "utf8",
    timeout: 120000,
    env: process.env,
  });
  const detail = (result.stdout || result.stderr || "").trim();
  if (detail) console.log(detail);
  return result.status === 0;
}

function textSubtitleStreams(source) {
  if (!fs.existsSync(FFPROBE)) return [];
  const result = spawnSync(FFPROBE, [
    "-v", "error",
    "-select_streams", "s",
    "-show_entries", "stream=index,codec_name",
    "-of", "json",
    source,
  ], { encoding: "utf8", timeout: 30000 });
  if (result.status !== 0) return [];
  try {
    const parsed = JSON.parse(result.stdout || "{}");
    return (parsed.streams || [])
      .filter((stream) => TEXT_SUBTITLE_CODECS.has(String(stream.codec_name || "").toLowerCase()))
      .map((stream) => Number(stream.index))
      .filter((index) => Number.isInteger(index));
  } catch {
    return [];
  }
}

function subtitleArgsForSource(source) {
  const args = [];
  for (const index of textSubtitleStreams(source)) args.push("-map", `0:${index}`);
  if (args.length > 0) args.push("-c:s", "mov_text");
  return args;
}

function subtitleTargets(filePath, lang = process.env.OPEN_SUBTITLES_LANGUAGE || process.env.SUBDL_LANGUAGE || "en") {
  const parsed = path.parse(filePath);
  return [
    path.join(parsed.dir, `${parsed.name}.${lang}.srt`),
    path.join(parsed.dir, `${parsed.name}.srt`),
    path.join(parsed.dir, `${parsed.name}.${lang}.vtt`),
    path.join(parsed.dir, `${parsed.name}.vtt`),
  ];
}

function firstSidecarSubtitle(filePath) {
  return subtitleTargets(filePath).find((candidate) => fs.existsSync(candidate)) || "";
}

function remuxSidecarSubtitleIntoMp4(target) {
  const subtitle = firstSidecarSubtitle(target);
  if (!subtitle) return false;
  const tmp = `${target}.subtmp.mp4`;
  fs.rmSync(tmp, { force: true });
  const result = spawnSync(FFMPEG, [
    "-hide_banner",
    "-loglevel", "warning",
    "-y",
    "-i", target,
    "-i", subtitle,
    "-map", "0",
    "-map", "1:0",
    "-c", "copy",
    "-c:s", "mov_text",
    "-movflags", "+faststart",
    tmp,
  ], { encoding: "utf8", timeout: 30 * 60 * 1000 });
  if (result.status !== 0) {
    fs.rmSync(tmp, { force: true });
    console.log(`[convert] subtitle remux failed ${target}: ${(result.stderr || result.stdout || "").trim().slice(0, 500)}`);
    return false;
  }
  fs.renameSync(tmp, target);
  return true;
}

function copySidecarSubtitles(source, target) {
  const sourceParsed = path.parse(source);
  const targetParsed = path.parse(target);
  const escapedBase = sourceParsed.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const sidecarRe = new RegExp(`^${escapedBase}(?:\\.[A-Za-z]{2,3})?\\.(srt|vtt)$`, "i");
  let copied = 0;
  for (const entry of fs.readdirSync(sourceParsed.dir, { withFileTypes: true })) {
    if (!entry.isFile() || !sidecarRe.test(entry.name)) continue;
    const suffix = entry.name.slice(sourceParsed.name.length);
    const destination = path.join(targetParsed.dir, `${targetParsed.name}${suffix}`);
    if (fs.existsSync(destination)) continue;
    fs.copyFileSync(path.join(sourceParsed.dir, entry.name), destination);
    copied += 1;
  }
  return copied;
}

function convertOne(source) {
  if (!fs.existsSync(source)) return { action: "skip", reason: "missing", source };
  const target = targetPathForSource(source);
  if (!target) return { action: "skip", reason: "no-normalized-target", source };
  if (path.resolve(source) === path.resolve(target)) return { action: "skip", reason: "already-target", source };
  if (fs.existsSync(target)) return { action: "skip", reason: "target-exists", source, target };
  if (DRY_RUN) return { action: "would-convert", source, target, deleteOriginal: DELETE_ORIGINAL };

  fs.mkdirSync(path.dirname(target), { recursive: true });
  const tmp = `${target}.tmp.mp4`;
  fs.rmSync(tmp, { force: true });
  const sourceTextSubtitleCount = textSubtitleStreams(source).length;
  const ffmpegArgs = [
    "-hide_banner",
    "-loglevel", "warning",
    "-y",
    "-i", source,
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-profile:v", "high",
    "-level", "4.0",
    "-pix_fmt", "yuv420p",
    "-vf", "scale='min(1280,iw)':-2",
    "-c:a", "aac",
    "-ac", "2",
    "-b:a", "160k",
    ...subtitleArgsForSource(source),
    "-movflags", "+faststart",
    tmp,
  ];
  const result = spawnSync(FFMPEG, ffmpegArgs, { encoding: "utf8", timeout: 24 * 60 * 60 * 1000 });

  if (result.status !== 0) {
    fs.rmSync(tmp, { force: true });
    return { action: "error", source, target, error: (result.stderr || result.stdout || `ffmpeg exited ${result.status}`).trim().slice(0, 500) };
  }
  fs.renameSync(tmp, target);
  const sidecarSubtitles = copySidecarSubtitles(source, target);
  generateVsmeta(source, target);
  downloadSubtitles(target);
  const embeddedDownloadedSubtitle = sourceTextSubtitleCount === 0 ? remuxSidecarSubtitleIntoMp4(target) : false;
  if (DELETE_ORIGINAL) {
    fs.rmSync(source, { force: true });
    fs.rmSync(`${source}.vsmeta`, { force: true });
  }
  indexReplacement(source, target);
  return { action: "converted", source, target, deleteOriginal: DELETE_ORIGINAL, sidecarSubtitles, embeddedDownloadedSubtitle };
}

function scanOnce() {
  const candidates = discoverCandidates();
  const summary = { checked: candidates.length, converted: 0, skipped: 0, errors: 0 };
  console.log(JSON.stringify({ action: "scan", candidates: candidates.length, dryRun: DRY_RUN, deleteOriginal: DELETE_ORIGINAL }));
  for (const source of candidates) {
    const result = convertOne(source);
    if (result.action === "converted" || result.action === "would-convert") summary.converted += 1;
    else if (result.action === "error") summary.errors += 1;
    else summary.skipped += 1;
    console.log(JSON.stringify(result));
  }
  console.log(JSON.stringify({ action: "summary", ...summary }));
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function acquireLock() {
  try {
    fs.writeFileSync(LOCK_FILE, String(process.pid), { flag: "wx" });
    process.on("exit", () => {
      try { fs.rmSync(LOCK_FILE, { force: true }); } catch {}
    });
  } catch {
    throw new Error(`converter already running or stale lock exists: ${LOCK_FILE}`);
  }
}

if (!fs.existsSync(FFMPEG)) throw new Error(`ffmpeg not found at ${FFMPEG}; set FFMPEG=/path/to/ffmpeg`);
acquireLock();
do {
  scanOnce();
  if (ONCE) break;
  sleep(Math.max(60, POLL_SECONDS) * 1000);
} while (WATCH);
