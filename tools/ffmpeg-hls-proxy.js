#!/usr/bin/env node
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { spawn } = require("child_process");
const { spawnSync } = require("child_process");

const HOST = process.env.ROKU_HLS_HOST || "0.0.0.0";
const PORT = Number(process.env.ROKU_HLS_PORT || 8099);
const BASE_URL = process.env.ROKU_HLS_BASE_URL || `http://127.0.0.1:${PORT}`;
const PATH_PREFIX = (process.env.ROKU_HLS_PATH_PREFIX || "").replace(/\/+$/, "");
const ROOT = process.env.ROKU_HLS_ROOT || path.join("/private/tmp", "roku-hls-proxy");
const FFMPEG = process.env.FFMPEG || "ffmpeg";
const AUDIO_CODEC = process.env.ROKU_HLS_AUDIO_CODEC || "aac";
const HTTPS_KEY = process.env.ROKU_HLS_HTTPS_KEY || "";
const HTTPS_CERT = process.env.ROKU_HLS_HTTPS_CERT || "";
const START_SEGMENTS = Number(process.env.ROKU_HLS_START_SEGMENTS || 6);
const IDLE_MS = Number(process.env.ROKU_HLS_IDLE_MS || 45000);
const CLEANUP_INTERVAL_MS = Number(process.env.ROKU_HLS_CLEANUP_INTERVAL_MS || 10000);
const SAVE_MP4 = process.env.ROKU_HLS_SAVE_MP4 !== "0";
const MP4_DIR = process.env.ROKU_HLS_MP4_DIR || path.join(ROOT, "mp4-cache");
const COPY_VSMETA = process.env.ROKU_HLS_COPY_VSMETA !== "0";
const VSMETA_GENERATOR = process.env.ROKU_HLS_VSMETA_GENERATOR || path.join(__dirname, "generate-vsmeta.js");
const SUBTITLE_DOWNLOADER = process.env.ROKU_HLS_SUBTITLE_DOWNLOADER || path.join(__dirname, "download-subtitles.js");
const NODE_BIN = process.env.ROKU_HLS_NODE || process.execPath;
const REPLACE_ORIGINAL = process.env.ROKU_HLS_REPLACE_ORIGINAL === "1";
const DELETE_REPLACED_ORIGINAL = process.env.ROKU_HLS_DELETE_REPLACED_ORIGINAL !== "0";

fs.mkdirSync(ROOT, { recursive: true });
if (SAVE_MP4) {
  cleanupStaleMp4Temps();
}

const sessions = new Map();

function touchSession(session) {
  if (session) session.lastAccessAt = Date.now();
}

function stopSession(id, reason = "idle") {
  const session = sessions.get(id);
  if (!session) return;
  if (reason === "idle" && session.exited && !session.mp4Finalized && !session.interrupted && session.exitCode === 0) {
    finalizeMp4(session, session.exitCode);
  }
  if (reason === "idle" && session.mp4Finalized && !session.replacementAttempted) {
    session.replacementAttempted = true;
    installReplacementForSession(session);
  }
  sessions.delete(id);
  console.log(`[proxy] stop ${id} reason=${reason}`);
  try {
    if (session.child && !session.exited) {
      session.interrupted = true;
      session.child.kill("SIGTERM");
      setTimeout(() => {
        try {
          if (!session.exited) session.child.kill("SIGKILL");
        } catch {
          // Process already exited.
        }
      }, 5000).unref?.();
    }
  } catch (err) {
    console.log(`[proxy] stop error ${id} ${err.message}`);
  }
  if ((!session.child || session.exited) && !session.mp4Finalized) {
    cleanupPartialMp4(session);
  }
  setTimeout(() => {
    try {
      fs.rmSync(session.dir, { recursive: true, force: true });
    } catch {
      // Best-effort temp cleanup.
    }
  }, 30000).unref?.();
}

function cleanupPartialMp4(session) {
  if (!session || !session.cacheTmp) return;
  try {
    if (fs.existsSync(session.cacheTmp)) fs.rmSync(session.cacheTmp, { force: true });
    cleanupMetadataForVideoPath(session.cacheTmp);
    cleanupFolderMetadata(path.dirname(session.cacheTmp));
    cleanupUnownedMp4Temps(path.dirname(session.cacheTmp));
    pruneEmptyDirs(path.dirname(session.cacheTmp), MP4_DIR, true);
  } catch (err) {
    console.log(`[proxy] mp4 cleanup error ${session.id} ${err.message}`);
  }
}

function cleanupUnownedMp4Temps(dir) {
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }

  const activeTemps = new Set();
  for (const active of sessions.values()) {
    if (active && active.cacheTmp) activeTemps.add(path.resolve(active.cacheTmp));
  }

  for (const entry of entries) {
    if (!entry.isFile() || (!entry.name.endsWith(".tmp") && !entry.name.endsWith(".tmp.mp4"))) continue;
    const filePath = path.join(dir, entry.name);
    if (activeTemps.has(path.resolve(filePath))) continue;
    try {
      fs.rmSync(filePath, { force: true });
      console.log(`[proxy] unowned tmp cleanup ${filePath}`);
    } catch (err) {
      console.log(`[proxy] unowned tmp cleanup error ${filePath} ${err.message}`);
    }
  }
}

function pruneEmptyDirs(startDir, stopDir, includeStop = false) {
  let current = startDir;
  const stop = path.resolve(stopDir);

  while (current && path.resolve(current).startsWith(stop)) {
    try {
      if (path.resolve(current) === stop && !includeStop) return;
      if (fs.existsSync(current) && fs.readdirSync(current).length === 0) {
        fs.rmdirSync(current);
      } else {
        return;
      }
    } catch {
      return;
    }

    if (path.resolve(current) === stop) return;
    current = path.dirname(current);
  }
}

function cleanupStaleMp4Temps(rootDir = MP4_DIR) {
  let removed = 0;
  let removedMetadata = 0;

  function visit(dir) {
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      const filePath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "@eaDir") {
          try {
            fs.rmSync(filePath, { recursive: true, force: true });
            removedMetadata += 1;
          } catch (err) {
            console.log(`[proxy] metadata cleanup error ${filePath} ${err.message}`);
          }
        } else {
          visit(filePath);
        }
      } else if (entry.isFile() && (entry.name.endsWith(".tmp") || entry.name.endsWith(".tmp.mp4"))) {
        try {
          fs.rmSync(filePath, { force: true });
          removed += 1;
        } catch (err) {
          console.log(`[proxy] stale tmp cleanup error ${filePath} ${err.message}`);
        }
      } else if (entry.isFile() && entry.name === ".DS_Store") {
        try {
          fs.rmSync(filePath, { force: true });
          removedMetadata += 1;
        } catch (err) {
          console.log(`[proxy] metadata cleanup error ${filePath} ${err.message}`);
        }
      }
    }

    try {
      if (dir !== rootDir && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
    } catch {
      // Best-effort empty folder cleanup.
    }
  }

  if (!fs.existsSync(rootDir)) return;
  visit(rootDir);
  pruneEmptyDirs(rootDir, rootDir, true);
  if (removed > 0) console.log(`[proxy] stale tmp cleanup removed ${removed} file(s)`);
  if (removedMetadata > 0) console.log(`[proxy] metadata cleanup removed ${removedMetadata} item(s)`);
}

function finalizeMp4(session, code) {
  if (!session || !session.cacheTmp || !session.cacheFinal) return;
  if (session.mp4Finalized) return;
  if (session.interrupted || code !== 0) {
    cleanupPartialMp4(session);
    return;
  }
  try {
    if (fs.existsSync(session.cacheTmp)) {
      fs.renameSync(session.cacheTmp, session.cacheFinal);
      console.log(`[proxy] mp4 saved ${session.id} ${session.cacheFinal}`);
      copyVsmetaForSession(session);
      session.mp4Finalized = true;
    } else if (!fs.existsSync(session.cacheFinal)) {
      console.log(`[proxy] mp4 finalize wait ${session.id} missing ${session.cacheTmp}`);
    }
  } catch (err) {
    console.log(`[proxy] mp4 finalize error ${session.id} ${err.message}`);
    cleanupPartialMp4(session);
  }
}

function nasPathCandidates(filePath) {
  const cleanPath = String(filePath || "").replace(/\\/g, "/");
  if (!cleanPath) return [];
  const paths = [];
  if (cleanPath.startsWith("/volume")) {
    paths.push(cleanPath);
  } else {
    const rooted = cleanPath.startsWith("/") ? cleanPath : `/${cleanPath}`;
    paths.push(rooted);
    paths.push(`/volume1${rooted}`);
    paths.push(`/volume2${rooted}`);
  }
  return [...new Set(paths)];
}

function findSourceVsmeta(src) {
  const filePath = sourceFilePath(src);
  for (const candidate of nasPathCandidates(filePath)) {
    const vsmeta = `${candidate}.vsmeta`;
    try {
      if (fs.existsSync(vsmeta)) return vsmeta;
    } catch {
      // Try the next candidate.
    }
  }
  return "";
}

function copyVsmetaForSession(session) {
  if (!COPY_VSMETA || !session || !session.cacheFinal) return;
  const source = findSourceVsmeta(session.src);
  const target = `${session.cacheFinal}.vsmeta`;
  if (!source) {
    if (generateVsmetaForSession(session, target)) return;
    const generated = generatedVsmetaForSource(session.src);
    if (generated.length === 0) {
      console.log(`[proxy] vsmeta source not found ${session.id}`);
      return;
    }
    try {
      fs.writeFileSync(target, generated);
      console.log(`[proxy] vsmeta generated ${session.id} ${target}`);
    } catch (err) {
      console.log(`[proxy] vsmeta generate error ${session.id} ${err.message}`);
    }
    return;
  }

  try {
    fs.copyFileSync(source, target);
    console.log(`[proxy] vsmeta saved ${session.id} ${target}`);
  } catch (err) {
    console.log(`[proxy] vsmeta copy error ${session.id} ${err.message}`);
  }
}

function generateVsmetaForSession(session, target) {
  const sourcePath = sourceFilePath(session.src);
  if (!sourcePath || !fs.existsSync(VSMETA_GENERATOR)) return false;
  try {
    const result = spawnSync(NODE_BIN, [VSMETA_GENERATOR, sourcePath, session.cacheFinal], {
      encoding: "utf8",
      timeout: 120000,
    });
    if (result.status === 0 && fs.existsSync(target)) {
      console.log(`[proxy] vsmeta generated-rich ${session.id} ${target}`);
      return true;
    }
    const detail = (result.stderr || result.stdout || `exit ${result.status}`).trim();
    console.log(`[proxy] vsmeta generator skipped ${session.id} ${detail}`);
  } catch (err) {
    console.log(`[proxy] vsmeta generator error ${session.id} ${err.message}`);
  }
  return false;
}

function sourceFilePath(src) {
  try {
    const url = new URL(src);
    return url.searchParams.get("path") || "";
  } catch {
    return "";
  }
}

function vsmetaVarint(num) {
  let value = Math.max(0, Number(num) || 0);
  const bytes = [];
  do {
    let byte = value & 0x7f;
    value = Math.floor(value / 128);
    if (value !== 0) byte |= 0x80;
    bytes.push(byte);
  } while (value !== 0);
  return Buffer.from(bytes);
}

function vsmetaString(value) {
  const bytes = Buffer.from(String(value || ""), "utf8");
  return Buffer.concat([vsmetaVarint(bytes.length), bytes]);
}

function vsmetaDate(value) {
  const text = String(value || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return Buffer.alloc(0);
  return Buffer.concat([Buffer.from([0x0a]), Buffer.from(text, "utf8")]);
}

function vsmetaTag(tag, value, kind = "string") {
  const tagBuffer = Buffer.isBuffer(tag) ? tag : Buffer.from([tag]);
  if (value === undefined || value === null) return tagBuffer;
  if (kind === "string") return Buffer.concat([tagBuffer, vsmetaString(value)]);
  if (kind === "int") return Buffer.concat([tagBuffer, vsmetaVarint(value)]);
  if (kind === "bool") return Buffer.concat([tagBuffer, Buffer.from([value ? 0x01 : 0x00])]);
  if (kind === "date") return Buffer.concat([tagBuffer, vsmetaDate(value)]);
  if (kind === "content") return Buffer.concat([tagBuffer, vsmetaVarint(value.length), value]);
  return tagBuffer;
}

function yearFromText(value) {
  const match = String(value || "").match(/\b(19\d{2}|20\d{2})\b/);
  return match ? Number(match[1]) : 0;
}

function generatedSeriesVsmeta(info) {
  const showTitle = cleanNamePart(info.show);
  const episodeTitle = cleanNamePart(info.title) || `Episode ${info.episode}`;
  if (!showTitle || !info.season || !info.episode) return Buffer.alloc(0);

  const group2 = Buffer.concat([
    vsmetaTag(0x08, info.season, "int"),
    vsmetaTag(0x10, info.episode, "int"),
    vsmetaTag(0x18, 0, "int"),
    vsmetaTag(0x28, true, "bool"),
  ]);

  return Buffer.concat([
    Buffer.from([0x08, 0x02]),
    vsmetaTag(0x12, showTitle),
    vsmetaTag(0x1a, showTitle),
    vsmetaTag(0x22, episodeTitle),
    vsmetaTag(0x38, true, "bool"),
    Buffer.from([0x9a]),
    vsmetaTag(0x01, group2, "content"),
  ]);
}

function generatedMovieVsmeta(info) {
  const title = cleanNamePart(info.title);
  if (!title) return Buffer.alloc(0);

  const chunks = [
    Buffer.from([0x08, 0x01]),
    vsmetaTag(0x12, title),
    vsmetaTag(0x1a, title),
  ];
  const year = yearFromText(title);
  if (year) {
    chunks.push(vsmetaTag(0x28, year, "int"));
    chunks.push(vsmetaTag(0x32, `${year}-01-01`, "date"));
  }
  chunks.push(vsmetaTag(0x38, true, "bool"));
  return Buffer.concat(chunks);
}

function generatedVsmetaForSource(src) {
  const filePath = sourceFilePath(src);
  const episodeInfo = episodeInfoFromPath(filePath);
  if (episodeInfo) return generatedSeriesVsmeta(episodeInfo);
  const movieInfo = movieInfoFromPath(filePath);
  if (movieInfo) return generatedMovieVsmeta(movieInfo);
  return Buffer.alloc(0);
}

function cleanNamePart(value) {
  return String(value || "")
    .replace(/[\\/:*?"<>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function withoutVideoExtension(value) {
  return String(value || "").replace(/\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts)$/i, "");
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
  if (norm === "movies" || norm === "movie") return "Movies";
  if (norm === "home videos" || norm === "home video") return "Home Videos";
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
  const beforeYear = baseName.slice(0, yearMatch.index).replace(/[.\-_]+/g, " ");
  const title = cleanNamePart(beforeYear);
  if (!title) return stripReleaseTail(baseName);
  return `${title} (${year})`;
}

function relativeFolderParts(parts, libraryIndex) {
  return parts.slice(libraryIndex + 1, -1).map(cleanNamePart).filter(Boolean);
}

function episodeInfoFromPath(filePath) {
  const cleanPath = String(filePath || "").replace(/\\/g, "/");
  const parts = cleanPath.split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => {
    const library = libraryNameForPart(part);
    return library === "TV Shows";
  });
  if (libraryIndex < 0 || parts.length <= libraryIndex + 2) return null;

  const show = cleanNamePart(parts[libraryIndex + 1]);
  const library = libraryNameForPart(parts[libraryIndex]) || "TV Shows";
  const fileName = parts[parts.length - 1] || "";
  const baseName = withoutVideoExtension(fileName).replace(/[._]+/g, " ");
  const seasonFolder = parts.slice(libraryIndex + 2, -1).find((part) => /^season\s+\d+/i.test(part));
  const seasonFromFolder = seasonFolder ? Number((seasonFolder.match(/\d+/) || ["0"])[0]) : 0;
  const episodeMatch = baseName.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || baseName.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  if (!episodeMatch && !seasonFromFolder) return null;

  const season = episodeMatch ? Number(episodeMatch[1]) : seasonFromFolder;
  const episode = episodeMatch ? Number(episodeMatch[2]) : 0;
  if (!season || !episode) return null;

  let fileShow = "";
  if (episodeMatch && episodeMatch.index > 0) {
    fileShow = cleanNamePart(baseName.slice(0, episodeMatch.index).replace(/[._-]+/g, " "));
  }
  const outputShow = fileShow && normalizeForCompare(fileShow).length >= normalizeForCompare(show).length ? fileShow : show;

  let title = baseName;
  const showNorm = normalizeForCompare(outputShow);
  const titleNorm = normalizeForCompare(title);
  if (showNorm && titleNorm.startsWith(showNorm + " ")) {
    title = title.slice(outputShow.length).trim();
  }
  title = title.replace(/\bS\d{1,2}E\d{1,3}\b/i, " ");
  title = stripReleaseTail(title.replace(/[._]+/g, " ").replace(/^[-\s]+|[-\s]+$/g, ""));

  return { library, show: outputShow, season, episode, title };
}

function seriesFallbackInfoFromPath(filePath) {
  const cleanPath = String(filePath || "").replace(/\\/g, "/");
  const parts = cleanPath.split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => {
    const library = libraryNameForPart(part);
    return library === "TV Shows";
  });
  if (libraryIndex < 0 || parts.length <= libraryIndex + 2) return null;

  const library = libraryNameForPart(parts[libraryIndex]) || "TV Shows";
  const show = cleanNamePart(parts[libraryIndex + 1]);
  const seasonFolder = parts.slice(libraryIndex + 2, -1).find((part) => /^season\s+\d+/i.test(part));
  const season = seasonFolder ? Number((seasonFolder.match(/\d+/) || ["0"])[0]) : 0;
  const fileName = parts[parts.length - 1] || "";
  const title = cleanNamePart(withoutVideoExtension(fileName).replace(/[._]+/g, " "));
  if (!show || !title) return null;
  return { library, show, season, title };
}

function movieInfoFromPath(filePath) {
  const cleanPath = String(filePath || "").replace(/\\/g, "/");
  const parts = cleanPath.split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => {
    const library = libraryNameForPart(part);
    return library === "Movies";
  });
  if (libraryIndex < 0 || parts.length <= libraryIndex + 1) return null;

  const fileName = parts[parts.length - 1] || "";
  const title = movieTitleFromFileName(fileName);
  if (!title) return null;
  return { library: libraryNameForPart(parts[libraryIndex]) || "Movies", title };
}

function homeVideoInfoFromPath(filePath) {
  const cleanPath = String(filePath || "").replace(/\\/g, "/");
  const parts = cleanPath.split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => libraryNameForPart(part) === "Home Videos");
  if (libraryIndex < 0 || parts.length <= libraryIndex + 1) return null;

  const fileName = parts[parts.length - 1] || "";
  const baseName = cleanNamePart(withoutVideoExtension(fileName).replace(/[._]+/g, " "));
  if (!baseName) return null;
  return { library: "Home Videos", folders: relativeFolderParts(parts, libraryIndex), title: baseName };
}

function mp4CachePaths(src, id) {
  const fallbackFinal = path.join(MP4_DIR, `${id}.mp4`);
  const tmpFor = (finalPath) => `${finalPath}.${id}.tmp.mp4`;
  const filePath = sourceFilePath(src);
  const info = episodeInfoFromPath(filePath);
  if (info) {
    const show = cleanNamePart(info.show) || id;
    const seasonText = String(info.season).padStart(2, "0");
    const episodeText = String(info.episode).padStart(2, "0");
    const seasonDir = `Season ${seasonText}`;
    const titlePart = info.title ? ` - ${cleanNamePart(info.title)}` : "";
    const fileName = `${show} - S${seasonText}E${episodeText}${titlePart}.mp4`;
    const library = cleanNamePart(info.library) || "TV Shows";
    const final = path.join(MP4_DIR, library, show, seasonDir, fileName);
    return { final, tmp: tmpFor(final) };
  }

  const seriesFallback = seriesFallbackInfoFromPath(filePath);
  if (seriesFallback) {
    const seasonDir = seriesFallback.season ? `Season ${String(seriesFallback.season).padStart(2, "0")}` : "Unknown Season";
    const fileName = `${cleanNamePart(seriesFallback.title) || id}.mp4`;
    const final = path.join(MP4_DIR, seriesFallback.library, seriesFallback.show, seasonDir, fileName);
    return { final, tmp: tmpFor(final) };
  }

  const movieInfo = movieInfoFromPath(filePath);
  if (movieInfo) {
    const fileName = `${cleanNamePart(movieInfo.title) || id}.mp4`;
    const movieDir = cleanNamePart(movieInfo.title) || id;
    const final = path.join(MP4_DIR, movieInfo.library, movieDir, fileName);
    return { final, tmp: tmpFor(final) };
  }

  const homeInfo = homeVideoInfoFromPath(filePath);
  if (homeInfo) {
    const fileName = `${cleanNamePart(homeInfo.title) || id}.mp4`;
    const final = path.join(MP4_DIR, homeInfo.library, ...homeInfo.folders, fileName);
    return { final, tmp: tmpFor(final) };
  }

  return { final: fallbackFinal, tmp: tmpFor(fallbackFinal) };
}

function sourceExistingPath(src) {
  const filePath = sourceFilePath(src);
  for (const candidate of nasPathCandidates(filePath)) {
    try {
      if (fs.existsSync(candidate)) return candidate;
    } catch {
      // Try next candidate.
    }
  }
  return "";
}

function libraryRootForSource(sourcePath, libraryName) {
  const cleanPath = String(sourcePath || "").replace(/\\/g, "/");
  const needle = `/${libraryName}/`;
  const idx = cleanPath.toLowerCase().indexOf(needle.toLowerCase());
  if (idx < 0) return "";
  return cleanPath.slice(0, idx + libraryName.length + 1);
}

function replacementPathForSource(sourcePath, id) {
  const info = episodeInfoFromPath(sourcePath);
  if (info) {
    const libraryRoot = libraryRootForSource(sourcePath, info.library);
    if (!libraryRoot) return "";
    const show = cleanNamePart(info.show) || id;
    const seasonText = String(info.season).padStart(2, "0");
    const episodeText = String(info.episode).padStart(2, "0");
    const titlePart = info.title ? ` - ${cleanNamePart(info.title)}` : "";
    const fileName = `${show} - S${seasonText}E${episodeText}${titlePart}.mp4`;
    return path.join(libraryRoot, show, `Season ${seasonText}`, fileName);
  }

  const seriesFallback = seriesFallbackInfoFromPath(sourcePath);
  if (seriesFallback) {
    const libraryRoot = libraryRootForSource(sourcePath, seriesFallback.library);
    if (!libraryRoot) return "";
    const seasonDir = seriesFallback.season ? `Season ${String(seriesFallback.season).padStart(2, "0")}` : "Unknown Season";
    const fileName = `${cleanNamePart(seriesFallback.title) || id}.mp4`;
    return path.join(libraryRoot, seriesFallback.show, seasonDir, fileName);
  }

  const movieInfo = movieInfoFromPath(sourcePath);
  if (movieInfo) {
    const libraryRoot = libraryRootForSource(sourcePath, movieInfo.library);
    if (!libraryRoot) return "";
    const movieDir = cleanNamePart(movieInfo.title) || id;
    const fileName = `${movieDir}.mp4`;
    return path.join(libraryRoot, movieDir, fileName);
  }

  const homeInfo = homeVideoInfoFromPath(sourcePath);
  if (homeInfo) {
    const libraryRoot = libraryRootForSource(sourcePath, homeInfo.library);
    if (!libraryRoot) return "";
    const fileName = `${cleanNamePart(homeInfo.title) || id}.mp4`;
    return path.join(libraryRoot, ...homeInfo.folders, fileName);
  }

  return "";
}

function safeCopyFile(source, target) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const tmp = `${target}.tmp`;
  fs.rmSync(tmp, { force: true });
  fs.copyFileSync(source, tmp);
  fs.renameSync(tmp, target);
}

function safeRemoveFile(filePath) {
  try {
    if (filePath && fs.existsSync(filePath)) fs.rmSync(filePath, { force: true });
  } catch (err) {
    console.log(`[proxy] remove error ${filePath} ${err.message}`);
  }
}

function cleanupMetadataForVideoPath(videoPath) {
  if (!videoPath) return;
  try {
    const metadataDir = path.join(path.dirname(videoPath), "@eaDir", path.basename(videoPath));
    fs.rmSync(metadataDir, { recursive: true, force: true });
    const metadataParent = path.dirname(metadataDir);
    if (fs.existsSync(metadataParent) && fs.readdirSync(metadataParent).length === 0) {
      fs.rmdirSync(metadataParent);
    }
  } catch (err) {
    console.log(`[proxy] metadata cleanup error ${videoPath} ${err.message}`);
  }
}

function cleanupFolderMetadata(dir) {
  if (!dir) return;
  for (const name of [".DS_Store", "@eaDir"]) {
    try {
      fs.rmSync(path.join(dir, name), { recursive: true, force: true });
    } catch {
      // Best-effort metadata cleanup.
    }
  }
}

function cleanupMetadataTreeToRoot(startDir, rootDir = MP4_DIR) {
  let current = path.resolve(startDir || "");
  const stop = path.resolve(rootDir || "");
  while (current && current.startsWith(stop)) {
    cleanupFolderMetadata(current);
    if (current === stop) break;
    current = path.dirname(current);
  }
}

function indexReplacement(sourcePath, targetPath) {
  const indexer = "/usr/syno/bin/synoindex";
  if (!fs.existsSync(indexer)) return;
  try {
    if (sourcePath) spawnSync(indexer, ["-d", sourcePath], { timeout: 30000 });
    if (targetPath) spawnSync(indexer, ["-a", targetPath], { timeout: 30000 });
  } catch (err) {
    console.log(`[proxy] synoindex error ${err.message}`);
  }
}

function downloadSubtitlesForPath(targetPath) {
  if (!process.env.SUBDL_API_KEY && !process.env.OPEN_SUBTITLES_API_KEY && !process.env.OPENSUBTITLES_API_KEY) return;
  if (!targetPath || !fs.existsSync(SUBTITLE_DOWNLOADER)) return;
  try {
    const result = spawnSync(NODE_BIN, [SUBTITLE_DOWNLOADER, targetPath], {
      encoding: "utf8",
      timeout: 120000,
      env: process.env,
    });
    const detail = (result.stdout || result.stderr || "").trim();
    if (detail) console.log(detail);
  } catch (err) {
    console.log(`[proxy] subtitle error ${targetPath} ${err.message}`);
  }
}

function sourceExistingPathFromFilePath(filePath) {
  for (const candidate of nasPathCandidates(filePath)) {
    try {
      if (fs.existsSync(candidate)) return candidate;
    } catch {
      // Try next candidate.
    }
  }
  return "";
}

async function resolveVideoStationItem(filePath) {
  const candidates = nasPathCandidates(filePath).map(sqlEscape).filter(Boolean);
  if (candidates.length === 0) return null;
  const inList = candidates.map((candidate) => `'${candidate}'`).join(",");
  const sql = `
    select row_to_json(x)
    from (
      select
        vf.id as file_id,
        vf.path as path,
        coalesce(e.id, m.id, hv.id, tr.id) as id,
        coalesce(e.mapper_id, m.mapper_id, hv.mapper_id, tr.mapper_id, vf.mapper_id) as mapper_id,
        case
          when e.id is not null then 'episode'
          when m.id is not null then 'movie'
          when hv.id is not null then 'homevideo'
          when tr.id is not null then 'homevideo'
          else ''
        end as type
      from video_file vf
      left join tvshow_episode e on e.mapper_id = vf.mapper_id
      left join movie m on m.mapper_id = vf.mapper_id
      left join home_video hv on hv.mapper_id = vf.mapper_id
      left join tv_record tr on tr.mapper_id = vf.mapper_id
      where vf.path in (${inList})
      order by
        case
          when e.id is not null then 1
          when m.id is not null then 2
          when hv.id is not null then 3
          when tr.id is not null then 4
          else 5
        end
      limit 1
    ) x`;
  const output = await runVideoStationSql(sql);
  if (!output) return null;
  return JSON.parse(output);
}

async function defaultWatchUid() {
  const configured = String(process.env.ROKU_HLS_WATCH_UID || "").replace(/[^0-9]/g, "");
  if (configured) return configured;
  const output = await runVideoStationSql("select uid from watch_status order by modify_date desc nulls last limit 1");
  return String(output || "1026").replace(/[^0-9]/g, "") || "1026";
}

async function updateVideoStationWatchStatus(filePath, position) {
  const item = await resolveVideoStationItem(filePath);
  if (!item || !item.file_id || !item.mapper_id) throw new Error("file not resolved");
  const uid = await defaultWatchUid();
  const fileId = String(item.file_id).replace(/[^0-9]/g, "");
  const mapperId = String(item.mapper_id).replace(/[^0-9]/g, "");
  const pos = Math.max(0, Number.parseInt(position, 10) || 0);
  if (!uid || !fileId || !mapperId) throw new Error("missing watch status ids");
  const sql = `
    with updated as (
      update watch_status
      set position = ${pos}, modify_date = now()
      where uid = ${uid} and video_file_id = ${fileId} and mapper_id = ${mapperId}
      returning id
    )
    insert into watch_status(uid, video_file_id, mapper_id, position, create_date, modify_date)
    select ${uid}, ${fileId}, ${mapperId}, ${pos}, now(), now()
    where not exists (select 1 from updated)
    returning id`;
  await runVideoStationSql(sql);
  console.log(`[proxy] watchstatus uid=${uid} file=${fileId} mapper=${mapperId} position=${pos}`);
  return { uid: Number(uid), file_id: Number(fileId), mapper_id: Number(mapperId), position: pos };
}

function installReplacementForSession(session) {
  if (!REPLACE_ORIGINAL || !session || !session.cacheFinal) return;
  const sourcePath = sourceExistingPath(session.src);
  if (!sourcePath) {
    console.log(`[proxy] replace skip ${session.id} source not found`);
    return;
  }
  const targetPath = replacementPathForSource(sourcePath, session.id);
  if (!targetPath) {
    console.log(`[proxy] replace skip ${session.id} no normalized target for ${sourcePath}`);
    return;
  }
  if (path.resolve(sourcePath) === path.resolve(targetPath)) {
    console.log(`[proxy] replace skip ${session.id} source already target`);
    return;
  }

  try {
    const cacheVsmeta = `${session.cacheFinal}.vsmeta`;
    const targetVsmeta = `${targetPath}.vsmeta`;
    if (fs.existsSync(targetPath)) {
      if (fs.statSync(targetPath).size === 0) throw new Error(`replacement target exists but is empty ${targetPath}`);
      console.log(`[proxy] replace target exists ${session.id} ${targetPath}`);
    } else {
      safeCopyFile(session.cacheFinal, targetPath);
    }
    if (fs.existsSync(cacheVsmeta)) {
      safeCopyFile(cacheVsmeta, targetVsmeta);
    } else if (!generateVsmetaForSession({ ...session, cacheFinal: targetPath }, targetVsmeta)) {
      const sourceVsmeta = findSourceVsmeta(session.src);
      if (sourceVsmeta) safeCopyFile(sourceVsmeta, targetVsmeta);
    }
    if (!fs.existsSync(targetPath) || fs.statSync(targetPath).size === 0) {
      throw new Error("replacement mp4 missing after copy");
    }
    if (DELETE_REPLACED_ORIGINAL) {
      safeRemoveFile(sourcePath);
      safeRemoveFile(`${sourcePath}.vsmeta`);
    }
    downloadSubtitlesForPath(targetPath);
    indexReplacement(sourcePath, targetPath);
    safeRemoveFile(session.cacheFinal);
    safeRemoveFile(cacheVsmeta);
    cleanupMetadataForVideoPath(session.cacheFinal);
    cleanupMetadataTreeToRoot(path.dirname(session.cacheFinal));
    pruneEmptyDirs(path.dirname(session.cacheFinal), MP4_DIR, true);
    console.log(`[proxy] replaced ${session.id} ${sourcePath} -> ${targetPath}`);
  } catch (err) {
    safeRemoveFile(targetPath);
    safeRemoveFile(`${targetPath}.vsmeta`);
    console.log(`[proxy] replace error ${session.id} ${err.message}`);
  }
}

function cleanupIdleSessions() {
  const now = Date.now();
  for (const [id, session] of sessions) {
    if (now - (session.lastAccessAt || session.createdAt || now) > IDLE_MS) {
      stopSession(id, "idle");
    }
  }
}

function send(res, status, headers, body) {
  res.writeHead(status, headers);
  res.end(body);
}

function sendJson(res, status, body) {
  const text = JSON.stringify(body || {});
  send(res, status, {
    "content-type": "application/json",
    "content-length": String(Buffer.byteLength(text)),
  }, text);
}

function contentTypeForVideo(filePath) {
  const lower = String(filePath || "").toLowerCase();
  if (lower.endsWith(".mov")) return "video/quicktime";
  return "video/mp4";
}

function serveVideoFile(req, res, filePath) {
  const sourcePath = sourceExistingPathFromFilePath(filePath);
  if (!sourcePath) return send(res, 404, { "content-type": "text/plain" }, "file not found");

  let stat;
  try {
    stat = fs.statSync(sourcePath);
  } catch {
    return send(res, 404, { "content-type": "text/plain" }, "file not found");
  }
  if (!stat.isFile()) return send(res, 404, { "content-type": "text/plain" }, "file not found");

  const size = stat.size;
  const range = String(req.headers.range || "");
  const headers = {
    "content-type": contentTypeForVideo(sourcePath),
    "accept-ranges": "bytes",
    "cache-control": "no-store",
  };

  if (range) {
    const match = range.match(/^bytes=(\d*)-(\d*)$/);
    if (!match) return send(res, 416, { "content-range": `bytes */${size}` }, "");
    let start = match[1] === "" ? 0 : Number(match[1]);
    let end = match[2] === "" ? size - 1 : Number(match[2]);
    if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end < start || start >= size) {
      return send(res, 416, { "content-range": `bytes */${size}` }, "");
    }
    end = Math.min(end, size - 1);
    headers["content-length"] = String(end - start + 1);
    headers["content-range"] = `bytes ${start}-${end}/${size}`;
    console.log(`[proxy] file range ${sourcePath} ${start}-${end}/${size}`);
    res.writeHead(206, headers);
    return fs.createReadStream(sourcePath, { start, end })
      .on("error", () => res.destroy())
      .pipe(res);
  }

  headers["content-length"] = String(size);
  console.log(`[proxy] file serve ${sourcePath}`);
  res.writeHead(200, headers);
  return fs.createReadStream(sourcePath)
    .on("error", () => res.destroy())
    .pipe(res);
}

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runVideoStationSql(sql, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const command = `psql -U VideoStation -d video_metadata -X -q -t -A -c "${sql.replace(/"/g, '\\"')}"`;
    const child = spawn("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error("metadata query timeout"));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("exit", (code) => {
      clearTimeout(timer);
      if (code !== 0) return reject(new Error(stderr.trim() || `psql exited ${code}`));
      resolve(stdout.trim());
    });
  });
}

async function tvMetadata(title) {
  const escapedTitle = sqlEscape(title);
  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.season, x.episode), '[]'::json)
    from (
      select *
      from (
        select
        e.season,
        e.episode,
        e.tag_line as title,
        coalesce(s.summary, '') as summary,
        vf.path as path,
        e.mapper_id,
        e.id,
        t.mapper_id as show_mapper_id,
        row_number() over (
          partition by e.id
          order by
            case when lower(coalesce(vf.path, '')) like '%short%' or lower(coalesce(vf.path, '')) like '%extra%' then 1 else 0 end,
            vf.path
        ) as rn
      from tvshow t
      join tvshow_episode e on e.tvshow_id = t.id
      left join summary s on s.mapper_id = e.mapper_id
      left join video_file vf on vf.mapper_id = e.mapper_id
      where lower(t.title) = lower('${escapedTitle}')
      ) ranked
      where rn = 1
    ) x`;
  const output = await runVideoStationSql(sql);
  return output || "[]";
}

function collectionIdForKey(key, collectionId) {
  const direct = Number(collectionId);
  if (Number.isInteger(direct) && direct > 0) return direct;
  if (key === "favorites") return 5;
  if (key === "watchlist") return 4;
  return 0;
}

async function toggleCollection(collectionId, mapperId, enabled) {
  const cid = Number(collectionId);
  const mid = Number(mapperId);
  if (!Number.isInteger(cid) || cid <= 0) throw new Error("invalid collection id");
  if (!Number.isInteger(mid) || mid <= 0) throw new Error("invalid mapper id");

  if (enabled) {
    await runVideoStationSql(`
      insert into collection_map (collection_id, mapper_id, create_date, modify_date)
      values (${cid}, ${mid}, now(), now())
      on conflict (collection_id, mapper_id)
      do update set modify_date = now()
    `);
    return { action: "added", collection_id: cid, mapper_id: mid };
  }

  await runVideoStationSql(`
    delete from collection_map
    where collection_id = ${cid}
      and mapper_id = ${mid}
  `);
  return { action: "removed", collection_id: cid, mapper_id: mid };
}

async function tvEpisodes(tvshowId, title) {
  const safeId = String(tvshowId || "").replace(/[^0-9]/g, "");
  const escapedTitle = sqlEscape(title);
  const conditions = [];
  if (safeId) {
    conditions.push(`t.id = ${safeId}`);
    conditions.push(`t.mapper_id = ${safeId}`);
  }
  if (escapedTitle) conditions.push(`lower(t.title) = lower('${escapedTitle}')`);
  if (conditions.length === 0) return "[]";

  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.season, x.episode, x.path), '[]'::json)
    from (
      select *
      from (
        select
          e.id,
          e.mapper_id,
          t.mapper_id as show_mapper_id,
          e.season,
          e.episode,
          e.tag_line as title,
          e.tag_line as name,
          coalesce(s.summary, '') as summary,
          coalesce(s.summary, '') as description,
          vf.path as path,
          json_build_object(
            'file',
            json_build_array(json_build_object('id', vf.id, 'path', vf.path))
          ) as additional,
          row_number() over (
            partition by e.id
            order by
              case when lower(coalesce(vf.path, '')) like '%short%' or lower(coalesce(vf.path, '')) like '%extra%' then 1 else 0 end,
              vf.path
          ) as rn
        from tvshow t
        join tvshow_episode e on e.tvshow_id = t.id
        left join summary s on s.mapper_id = e.mapper_id
        left join video_file vf on vf.mapper_id = e.mapper_id
        where (${conditions.join(" or ")})
          and vf.path is not null
      ) ranked
      where rn = 1
    ) x`;
  const output = await runVideoStationSql(sql);
  const items = mergeEpisodeItems(output || "[]", filesystemEpisodesForShow(title));
  await attachWatchPositions(items);
  return JSON.stringify(items);
}

function mergeEpisodeItems(databaseJson, fallbackItems) {
  let items = [];
  try {
    items = JSON.parse(databaseJson || "[]");
  } catch {
    items = [];
  }
  const merged = Array.isArray(items) ? [...items] : [];
  for (const item of fallbackItems || []) {
    const existingIndex = merged.findIndex((candidate) => episodeMergeKey(candidate) === episodeMergeKey(item));
    if (existingIndex < 0) {
      merged.push(item);
    } else if (episodeItemCompleteness(item) > episodeItemCompleteness(merged[existingIndex])) {
      merged[existingIndex] = { ...merged[existingIndex], ...item };
    }
  }
  return merged;
}

async function attachWatchPositions(items) {
  if (!Array.isArray(items) || items.length === 0) return items;
  const candidates = [];
  for (const item of items) {
    for (const candidate of nasPathCandidates(item?.path || item?.additional?.file?.[0]?.path || "")) {
      if (candidate) candidates.push(candidate);
    }
  }
  const uniqueCandidates = [...new Set(candidates.map(sqlEscape).filter(Boolean))];
  if (uniqueCandidates.length === 0) return items;
  const uid = await defaultWatchUid();
  const inList = uniqueCandidates.map((candidate) => `'${candidate}'`).join(",");
  const sql = `
    select coalesce(json_object_agg(path, position), '{}'::json)
    from (
      select distinct on (vf.path)
        vf.path,
        coalesce(ws.position, 0) as position
      from video_file vf
      left join watch_status ws on ws.video_file_id = vf.id and ws.mapper_id = vf.mapper_id and ws.uid = ${uid}
      where vf.path in (${inList})
      order by vf.path, ws.modify_date desc nulls last
    ) x`;
  let positions = {};
  try {
    positions = JSON.parse(await runVideoStationSql(sql) || "{}");
  } catch {
    positions = {};
  }
  for (const item of items) {
    const pathValue = item?.path || item?.additional?.file?.[0]?.path || "";
    let position = 0;
    for (const candidate of nasPathCandidates(pathValue)) {
      const value = positions[candidate];
      if (value !== undefined && value !== null) {
        position = Number(value) || 0;
        break;
      }
    }
    if (position > 0) {
      item.watch_position = position;
      item.resumePosition = position;
    }
  }
  return items;
}

function episodeMergeKey(item) {
  return `${Number(item?.season || item?.season_number || 0)}x${Number(item?.episode || item?.episode_number || 0)}`;
}

function episodeItemCompleteness(item) {
  let score = 0;
  if (item?.path) score += 10;
  if (item?.additional?.file?.[0]?.path) score += 10;
  if (item?.mapper_id) score += 4;
  if (item?.summary || item?.description) score += 2;
  if (item?.title || item?.name) score += 1;
  return score;
}

function filesystemEpisodesForShow(title) {
  const cleanTitle = cleanNamePart(title);
  if (!cleanTitle) return [];
  const roots = [
    "/volume1/video/TV Shows",
    "/volume1/video/TV",
    "/volume1/video/Series",
    "/volume2/video/TV Shows",
    "/volume2/video/TV",
    "/volume2/video/Series",
  ];
  const showDirs = [];
  for (const root of roots) {
    const direct = path.join(root, cleanTitle);
    try {
      if (fs.existsSync(direct) && fs.statSync(direct).isDirectory()) showDirs.push(direct);
    } catch {
      // Try the next candidate.
    }
  }
  if (showDirs.length === 0) return [];

  const items = [];
  for (const showDir of showDirs) collectEpisodeFilesFromDisk(showDir, 2, items);
  return items;
}

function collectEpisodeFilesFromDisk(dir, depth, items) {
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    const filePath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (depth > 0 && entry.name !== "@eaDir") collectEpisodeFilesFromDisk(filePath, depth - 1, items);
      continue;
    }
    if (!entry.isFile() || !isVideoFileName(entry.name)) continue;
    const info = episodeInfoFromPath(filePath);
    if (!info || !info.season || !info.episode) continue;
    const stationPath = fileStationPath(filePath);
    const id = crypto.createHash("sha1").update(stationPath).digest("hex").slice(0, 12);
    const title = cleanNamePart(info.title) || `Episode ${info.episode}`;
    items.push({
      id,
      file_id: id,
      season: info.season,
      season_number: info.season,
      episode: info.episode,
      episode_number: info.episode,
      ep_num: info.episode,
      title,
      name: title,
      path: stationPath,
      additional: { file: [{ id, path: stationPath }] },
    });
  }
}

function isVideoFileName(fileName) {
  return /\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts)$/i.test(String(fileName || ""));
}

function fileStationPath(nasPath) {
  return String(nasPath || "").replace(/^\/volume\d+/, "") || nasPath;
}

async function posterBuffer(mapperId, fallbackMapperId = "") {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) throw new Error("missing mapper_id");
  const isShowMapper = await isTvShowMapper(safeId);
  const isEpisode = await isEpisodeMapper(safeId);

  if (isEpisode) {
    const sidecarImage = await vsmetaImageForMapper(safeId, "poster");
    if (sidecarImage) return sidecarImage;
    const generated = await generatedVideoPosterBuffer(safeId);
    if (generated) return generated;
  }

  const sql = `select encode(lo_get(lo_oid), 'base64') from poster where mapper_id = ${safeId} limit 1`;
  const output = await runVideoStationSql(sql);
  if (output) return Buffer.from(output.replace(/\s+/g, ""), "base64");

  if (!isEpisode) {
    const sidecarImage = await vsmetaImageForMapper(safeId, "poster");
    if (sidecarImage) return sidecarImage;
  }

  if (!isShowMapper) {
    const generated = await generatedVideoPosterBuffer(safeId);
    if (generated) return generated;
  }
  const safeFallback = String(fallbackMapperId || "").replace(/[^0-9]/g, "");
  if (safeFallback) {
    const fallbackPoster = await posterBuffer(safeFallback, "");
    if (fallbackPoster) return fallbackPoster;
    return backdropBuffer(safeFallback);
  }
  throw new Error("poster not found");
}

async function isEpisodeMapper(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return false;
  const output = await runVideoStationSql(`select 1 from tvshow_episode where mapper_id = ${safeId} or id = ${safeId} limit 1`);
  return String(output || "").trim() === "1";
}

async function isTvShowMapper(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return false;
  const output = await runVideoStationSql(`select 1 from tvshow where mapper_id = ${safeId} limit 1`);
  return String(output || "").trim() === "1";
}

async function generatedVideoPosterBuffer(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return null;
  const sql = `select path from video_file where mapper_id = ${safeId} order by id limit 1`;
  const videoPath = await runVideoStationSql(sql);
  if (!videoPath) return null;

  const dir = path.dirname(videoPath);
  const base = path.basename(videoPath);
  const thumbDir = path.join(dir, "@eaDir", base);
  const candidates = [
    path.join(thumbDir, "SYNOVIDEO_VIDEO_POSTER.jpg"),
    path.join(thumbDir, "SYNOVIDEO_VIDEO_POSTER_JPEGTN.jpg"),
    path.join(thumbDir, "SYNOVIDEO_VIDEO_SCREENSHOT.jpg"),
    path.join(thumbDir, "SYNOVIDEO_VIDEO_SCREENSHOT_JPEGTN.jpg"),
  ];

  for (const candidate of candidates) {
    try {
      if (fs.existsSync(candidate)) return fs.readFileSync(candidate);
    } catch {
      // Try the next generated thumbnail candidate.
    }
  }
  return null;
}

async function backdropBuffer(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) throw new Error("missing mapper_id");
  const sql = `select encode(lo_get(lo_oid), 'base64') from backdrop where mapper_id = ${safeId} limit 1`;
  const output = await runVideoStationSql(sql);
  if (output) return Buffer.from(output.replace(/\s+/g, ""), "base64");

  const sidecarImage = await vsmetaImageForMapper(safeId, "backdrop");
  if (sidecarImage) return sidecarImage;

  const showMapperId = await showMapperIdForEpisode(safeId);
  if (showMapperId && showMapperId !== safeId) return backdropBuffer(showMapperId);
  throw new Error("backdrop not found");
}

async function showMapperIdForEpisode(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return "";
  const sql = `
    select t.mapper_id
    from tvshow_episode e
    join tvshow t on t.id = e.tvshow_id
    where e.mapper_id = ${safeId} or e.id = ${safeId}
    limit 1`;
  return await runVideoStationSql(sql);
}

async function libraryItems(libraryId, type) {
  const safeLibraryId = String(libraryId || "").replace(/[^0-9]/g, "");

  const normalizedType = String(type || "").toLowerCase();
  let table = "";
  if (normalizedType === "movie") table = "movie";
  if (normalizedType === "tvshow") table = "tvshow";
  if (normalizedType === "homevideo" || normalizedType === "home_video") table = "home_video";
  if (!table) return "[]";

  const dateExpr = table === "home_video" ? "record_time::text" : "originally_available::text";
  const yearExpr = table === "home_video" ? "extract(year from record_time)::int" : "year";
  const libraryWhere = safeLibraryId ? `x0.library_id = ${safeLibraryId}` : "x0.library_id is null";
  const tvShowExtra = table === "tvshow" ? ", (select count(*) from tvshow_episode e where e.tvshow_id = x0.id) as episode_count" : "";
  const summaryJoin = table === "home_video" ? "" : "left join summary s on s.mapper_id = x0.mapper_id";
  const summarySelect = table === "home_video" ? "" : ", coalesce(s.summary, '') as summary, coalesce(s.summary, '') as description";
  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.sort_title, x.title), '[]'::json)
    from (
      select x0.id, x0.mapper_id, x0.title, x0.sort_title, x0.library_id, ${yearExpr.replace(/\b(record_time|year)\b/g, "x0.$1")} as year, ${dateExpr.replace(/\b(record_time|originally_available)\b/g, "x0.$1")} as original_available${summarySelect}${tvShowExtra}
      from ${table} x0
      ${summaryJoin}
      where ${libraryWhere}
      order by x0.sort_title, x0.title
    ) x`;
  const output = await runVideoStationSql(sql);
  if (table === "tvshow") return JSON.stringify(mergeDuplicateTvShows(output || "[]"));
  return output || "[]";
}

function normalizedShowTitle(value) {
  return normalizeForCompare(String(value || "").replace(/\bthe\b/gi, ""));
}

function mergeDuplicateTvShows(jsonText) {
  let items = [];
  try {
    items = JSON.parse(jsonText || "[]");
  } catch {
    items = [];
  }
  const byTitle = new Map();
  for (const item of items) {
    const key = normalizedShowTitle(item.title);
    if (!key) continue;
    const existing = byTitle.get(key);
    const candidates = [
      ...(item.idCandidates || []),
      item.id,
      item.mapper_id,
      item.tvshow_id,
    ].filter((value) => value !== undefined && value !== null && String(value) !== "" && String(value) !== "0");
    item.idCandidates = [...new Set(candidates.map((value) => String(value)))];
    if (!existing) {
      byTitle.set(key, item);
      continue;
    }
    const existingCount = Number(existing.episode_count || 0);
    const itemCount = Number(item.episode_count || 0);
    const keep = itemCount > existingCount ? item : existing;
    const other = keep === item ? existing : item;
    keep.idCandidates = [...new Set([...(keep.idCandidates || []), ...(other.idCandidates || [])].map((value) => String(value)))];
    if (!keep.posterUrl && other.posterUrl) keep.posterUrl = other.posterUrl;
    if (!keep.backdropUrl && other.backdropUrl) keep.backdropUrl = other.backdropUrl;
    byTitle.set(key, keep);
  }
  return [...byTitle.values()];
}

function readVsmetaVarint(buffer, offset) {
  let value = 0;
  let shift = 0;
  let cursor = offset;
  while (cursor < buffer.length) {
    const byte = buffer[cursor];
    value += (byte & 0x7f) * (2 ** shift);
    cursor += 1;
    if ((byte & 0x80) === 0) return { value, offset: cursor };
    shift += 7;
    if (shift > 35) break;
  }
  return null;
}

function readVsmetaString(buffer, offset) {
  const lengthInfo = readVsmetaVarint(buffer, offset);
  if (!lengthInfo) return "";
  const end = lengthInfo.offset + lengthInfo.value;
  if (lengthInfo.value <= 0 || end > buffer.length) return "";
  return buffer.slice(lengthInfo.offset, end).toString("utf8");
}

function decodeVsmetaImageText(value) {
  const compact = String(value || "").replace(/\s+/g, "");
  if (compact.length < 32) return null;
  try {
    const data = Buffer.from(compact, "base64");
    if (data.length < 128) return null;
    return data;
  } catch {
    return null;
  }
}

function directVsmetaImage(buffer, marker) {
  for (let i = 0; i < buffer.length - 2; i += 1) {
    if (buffer[i] !== marker) continue;
    const text = readVsmetaString(buffer, i + 1);
    const image = decodeVsmetaImageText(text);
    if (image) return image;
  }
  return null;
}

function indexedVsmetaImage(buffer, marker) {
  for (let i = 0; i < buffer.length - 3; i += 1) {
    if (buffer[i] !== marker) continue;
    const index = buffer[i + 1];
    if (index < 1 || index > 8) continue;
    const text = readVsmetaString(buffer, i + 2);
    const image = decodeVsmetaImageText(text);
    if (image) return image;
  }
  return null;
}

function contentAfterMarker(buffer, marker) {
  for (let i = 0; i < buffer.length - 3; i += 1) {
    if (buffer[i] !== marker) continue;
    let start = i + 1;
    if (buffer[start] >= 1 && buffer[start] <= 8) start += 1;
    const lengthInfo = readVsmetaVarint(buffer, start);
    if (!lengthInfo) continue;
    const end = lengthInfo.offset + lengthInfo.value;
    if (lengthInfo.value <= 0 || end > buffer.length) continue;
    return buffer.slice(lengthInfo.offset, end);
  }
  return null;
}

function extractVsmetaImage(buffer, kind, role) {
  if (!buffer || buffer.length === 0) return null;
  if (kind === "poster") {
    if (role === "show") {
      return directVsmetaImage(buffer, 0x3a) || indexedVsmetaImage(buffer, 0x8a);
    }
    return indexedVsmetaImage(buffer, 0x8a) || directVsmetaImage(buffer, 0x3a);
  }

  const movieBackdropContent = contentAfterMarker(buffer, 0xaa);
  if (movieBackdropContent) {
    const image = directVsmetaImage(movieBackdropContent, 0x0a);
    if (image) return image;
  }

  const showBackdropContent = contentAfterMarker(buffer, 0x52);
  if (showBackdropContent) {
    const image = directVsmetaImage(showBackdropContent, 0x0a);
    if (image) return image;
  }

  return null;
}

async function vsmetaVideoCandidates(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return [];
  const sql = `
    select role || E'\t' || path
    from (
      select 'direct' as role, vf.path as path, 0 as rank
      from video_file vf
      where vf.mapper_id = ${safeId}
      union all
      select 'show' as role, vf.path as path, 1 as rank
      from tvshow t
      join tvshow_episode e on e.tvshow_id = t.id
      join video_file vf on vf.mapper_id = e.mapper_id
      where t.mapper_id = ${safeId}
    ) x
    where path is not null
    order by rank, path
    limit 12`;
  const output = await runVideoStationSql(sql);
  if (!output) return [];
  return output.split("\n").map((line) => {
    const parts = line.split("\t");
    return { role: parts[0] || "direct", path: parts.slice(1).join("\t") };
  }).filter((item) => item.path);
}

async function vsmetaImageForMapper(mapperId, kind) {
  let candidates = [];
  try {
    candidates = await vsmetaVideoCandidates(mapperId);
  } catch (err) {
    console.log(`[proxy] vsmeta lookup error mapper=${mapperId} ${err.message}`);
    return null;
  }
  for (const candidate of candidates) {
    for (const videoPath of nasPathCandidates(candidate.path)) {
      const sidecar = `${videoPath}.vsmeta`;
      try {
        if (!fs.existsSync(sidecar)) continue;
        const image = extractVsmetaImage(fs.readFileSync(sidecar), kind, candidate.role);
        if (image) {
          console.log(`[proxy] vsmeta ${kind} mapper=${mapperId} role=${candidate.role}`);
          return image;
        }
      } catch (err) {
        console.log(`[proxy] vsmeta read error ${sidecar} ${err.message}`);
      }
    }
  }
  return null;
}

function localSourceUrl(srcUrl) {
  const localHost = process.env.ROKU_HLS_SOURCE_HOST || "127.0.0.1";
  const next = new URL(srcUrl.toString());
  next.hostname = localHost;
  return next.toString();
}

function shouldRetrySourceLocally(err) {
  const code = err && err.code ? String(err.code) : "";
  return code === "EAI_AGAIN" || code === "ENOTFOUND";
}

function pipeSourceToFfmpeg(src, child, id, redirectCount = 0, triedLocal = false) {
  let srcUrl;
  try {
    srcUrl = new URL(src);
  } catch (err) {
    child.stdin.destroy(err);
    return;
  }

  const client = srcUrl.protocol === "https:" ? https : http;
  const req = client.get(srcUrl, { rejectUnauthorized: false }, (res) => {
    if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && redirectCount < 5) {
      res.resume();
      const next = new URL(res.headers.location, srcUrl).toString();
      pipeSourceToFfmpeg(next, child, id, redirectCount + 1, triedLocal);
      return;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      console.log(`[proxy] source http ${id} status=${res.statusCode}`);
      res.resume();
      child.stdin.destroy(new Error(`source status ${res.statusCode}`));
      return;
    }

    res.pipe(child.stdin);
  });

  req.on("error", (err) => {
    console.log(`[proxy] source error ${id} ${err.message}`);
    if (!triedLocal && shouldRetrySourceLocally(err)) {
      const next = localSourceUrl(srcUrl);
      console.log(`[proxy] source retry-local ${id} ${srcUrl.host} -> ${new URL(next).host}`);
      pipeSourceToFfmpeg(next, child, id, redirectCount, true);
      return;
    }
    child.stdin.destroy(err);
  });
}

function sessionFor(src) {
  const id = crypto.createHash("sha1").update(src).digest("hex").slice(0, 16);
  let session = sessions.get(id);
  if (session) return session;

  const dir = path.join(ROOT, id);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  const playlist = path.join(dir, "index.m3u8");
  const cachePaths = SAVE_MP4 ? mp4CachePaths(src, id) : { final: "", tmp: "" };
  const cacheFinal = cachePaths.final;
  const cacheTmp = cachePaths.tmp;
  if (cacheTmp) {
    fs.mkdirSync(path.dirname(cacheTmp), { recursive: true });
    fs.rmSync(cacheTmp, { force: true });
  }
  const outputArgs = SAVE_MP4 ? [
    "-f", "tee",
    `[f=hls:hls_time=4:hls_list_size=0:hls_flags=independent_segments:hls_segment_filename=${path.join(dir, "seg_%05d.ts")}]${playlist}|[f=mp4:movflags=+faststart:onfail=ignore]${cacheTmp}`,
  ] : [
    "-f", "hls",
    "-hls_time", "4",
    "-hls_list_size", "0",
    "-hls_flags", "independent_segments",
    "-hls_segment_filename", path.join(dir, "seg_%05d.ts"),
    playlist,
  ];
  const args = [
    "-hide_banner",
    "-loglevel", "warning",
    "-fflags", "+genpts",
    "-i", "pipe:0",
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-profile:v", "high",
    "-level", "4.0",
    "-pix_fmt", "yuv420p",
    "-g", "120",
    "-keyint_min", "120",
    "-sc_threshold", "0",
    "-force_key_frames", "expr:gte(t,n_forced*4)",
    "-vf", "scale='min(1280,iw)':-2",
    "-c:a", AUDIO_CODEC,
    "-ac", "2",
    "-b:a", "160k",
    "-max_muxing_queue_size", "1024",
    "-avoid_negative_ts", "make_zero",
    ...outputArgs,
  ];

  console.log(`[proxy] start ${id} saveMp4=${SAVE_MP4}${cacheFinal ? ` mp4=${cacheFinal}` : ""}`);
  const child = spawn(FFMPEG, args, { stdio: ["pipe", "ignore", "pipe"] });
  child.stdin.on("error", (err) => {
    console.log(`[proxy] stdin error ${id} ${err.code || err.message}`);
  });
  pipeSourceToFfmpeg(src, child, id);
  child.stderr.on("data", (chunk) => {
    const text = chunk.toString().trim();
    if (text) console.log(`[ffmpeg ${id}] ${text}`);
  });
  child.on("exit", (code, signal) => {
    console.log(`[proxy] ffmpeg exit ${id} code=${code} signal=${signal}`);
  });
  child.on("close", (code, signal) => {
    console.log(`[proxy] ffmpeg close ${id} code=${code} signal=${signal}`);
    const s = session || sessions.get(id);
    if (s) {
      s.exited = true;
      s.exitCode = code;
      s.signal = signal;
      finalizeMp4(s, code);
    }
  });

  session = { id, src, dir, playlist, child, createdAt: Date.now(), lastAccessAt: Date.now(), exited: false, interrupted: false, cacheFinal, cacheTmp };
  sessions.set(id, session);
  return session;
}

function waitForPlaylist(file, deadlineMs) {
  return new Promise((resolve) => {
    const started = Date.now();
    const tick = () => {
      if (fs.existsSync(file) && fs.statSync(file).size > 0) return resolve(true);
      if (Date.now() - started >= deadlineMs) return resolve(false);
      setTimeout(tick, 250);
    };
    tick();
  });
}

function readySegmentCount(session) {
  let count = 0;
  for (let i = 0; i < START_SEGMENTS; i += 1) {
    const file = path.join(session.dir, `seg_${String(i).padStart(5, "0")}.ts`);
    if (fs.existsSync(file) && fs.statSync(file).size > 0) count += 1;
  }
  return count;
}

function segmentReady(session, index) {
  const file = path.join(session.dir, `seg_${String(index).padStart(5, "0")}.ts`);
  return fs.existsSync(file) && fs.statSync(file).size > 0;
}

function waitForInitialSegments(session, deadlineMs, resumeSeconds = 0) {
  return new Promise((resolve) => {
    const started = Date.now();
    const resumeSegment = Math.max(0, Math.floor((Number(resumeSeconds) || 0) / 4));
    const targetSegment = resumeSegment > 0 ? resumeSegment : START_SEGMENTS - 1;
    const tick = () => {
      touchSession(session);
      const count = readySegmentCount(session);
      if (resumeSegment > 0) {
        if (segmentReady(session, targetSegment)) return resolve(true);
      } else if (count >= START_SEGMENTS) {
        return resolve(true);
      }
      if (Date.now() - started >= deadlineMs) return resolve(resumeSegment > 0 ? segmentReady(session, Math.max(0, targetSegment - 1)) : count > 0);
      setTimeout(tick, 250);
    };
    tick();
  });
}

function initialSegmentDeadlineMs(resumeSeconds) {
  const resume = Math.max(0, Number(resumeSeconds) || 0);
  if (resume <= 0) return 30000;
  return Math.max(30000, Math.min(180000, Math.ceil((resume + 20) * 1000)));
}

function publicBaseUrl(req) {
  if (process.env.ROKU_HLS_BASE_URL) return process.env.ROKU_HLS_BASE_URL;
  const forwardedProto = (req.headers["x-forwarded-proto"] || "").split(",")[0].trim();
  const forwardedHost = (req.headers["x-forwarded-host"] || "").split(",")[0].trim();
  const proto = forwardedProto || (req.socket.encrypted ? "https" : "http");
  const host = forwardedHost || req.headers.host || `127.0.0.1:${PORT}`;
  return `${proto}://${host}${PATH_PREFIX}`;
}

function rewritePlaylist(session, req) {
  const base = publicBaseUrl(req);
  let text = fs.readFileSync(session.playlist, "utf8");
  text = text.replace(/^(seg_\d+\.ts)$/gm, `${base}/hls/${session.id}/$1`);
  return text;
}

async function handleRequest(req, res) {
  const url = new URL(req.url, BASE_URL);
  let requestPath = url.pathname;
  if (PATH_PREFIX && requestPath.startsWith(PATH_PREFIX + "/")) {
    requestPath = requestPath.slice(PATH_PREFIX.length);
  }

  if (requestPath === "/health") {
    return send(res, 200, { "content-type": "application/json" }, JSON.stringify({ ok: true, sessions: sessions.size }));
  }

  if (requestPath === "/transcode") {
    const src = url.searchParams.get("src");
    const resumeSeconds = Number(url.searchParams.get("resume") || 0);
    if (!src) return send(res, 400, { "content-type": "text/plain" }, "missing src");
    const session = sessionFor(src);
    let playlistSent = false;
    req.on("close", () => {
      if (!playlistSent) {
        touchSession(session);
        console.log(`[proxy] transcode request closed before playlist ${session.id}; keeping session alive`);
      }
    });
    touchSession(session);
    const ready = await waitForPlaylist(session.playlist, 20000);
    if (!ready) return send(res, 504, { "content-type": "text/plain" }, "playlist not ready");
    const segmentsReady = await waitForInitialSegments(session, initialSegmentDeadlineMs(resumeSeconds), resumeSeconds);
    if (!segmentsReady) return send(res, 504, { "content-type": "text/plain" }, "segments not ready");
    console.log(`[proxy] playlist ${session.id} resume=${resumeSeconds}`);
    playlistSent = true;
    return send(res, 200, {
      "content-type": "application/vnd.apple.mpegurl",
      "cache-control": "no-store",
    }, rewritePlaylist(session, req));
  }

  const match = requestPath.match(/^\/hls\/([a-f0-9]{16})\/(.+)$/);
  if (match) {
    const [, id, name] = match;
    const session = sessions.get(id);
    if (!session) return send(res, 404, { "content-type": "text/plain" }, "unknown session");
    touchSession(session);
    const file = path.join(session.dir, path.basename(name));
    if (!fs.existsSync(file)) return send(res, 404, { "content-type": "text/plain" }, "not ready");
    console.log(`[proxy] segment ${id}/${path.basename(name)}`);
    const type = name.endsWith(".m3u8") ? "application/vnd.apple.mpegurl" : "video/mp2t";
    res.writeHead(200, { "content-type": type, "cache-control": "no-store" });
    const stream = fs.createReadStream(file);
    stream.on("error", () => {
      if (!res.headersSent) res.writeHead(404, { "content-type": "text/plain" });
      res.end("segment read failed");
    });
    res.on("close", () => {
      touchSession(session);
    });
    stream.pipe(res);
    return;
  }

  send(res, 404, { "content-type": "text/plain" }, "not found");
}

function createServer() {
  if (HTTPS_KEY && HTTPS_CERT) {
    return https.createServer({
      key: fs.readFileSync(HTTPS_KEY),
      cert: fs.readFileSync(HTTPS_CERT),
    }, handleRequest);
  }

  return http.createServer(handleRequest);
}

const server = createServer();

setInterval(cleanupIdleSessions, CLEANUP_INTERVAL_MS).unref?.();

server.listen(PORT, HOST, () => {
  if (HTTPS_KEY && HTTPS_CERT) {
    console.log(`[proxy] listening on https://127.0.0.1:${PORT}`);
  } else {
    console.log(`[proxy] listening on ${BASE_URL}`);
  }
  console.log(`[proxy] temp root ${ROOT}`);
  console.log(`[proxy] idle cleanup ${IDLE_MS}ms`);
  console.log(`[proxy] save mp4 ${SAVE_MP4 ? "enabled" : "disabled"}${SAVE_MP4 ? ` dir=${MP4_DIR}` : ""}`);
});
