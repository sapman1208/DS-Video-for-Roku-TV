#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
const root = valueAfter("--root") || "/volume1/video/TV Shows";
const show = valueAfter("--show") || "";
const seasonMin = Number(valueAfter("--season-min") || valueAfter("--season") || 1);
const seasonMax = Number(valueAfter("--season-max") || valueAfter("--season") || seasonMin);
const episodeMin = Number(valueAfter("--episode-min") || 1);
const episodeMax = Number(valueAfter("--episode-max") || 999);
const limit = Number(valueAfter("--limit") || 0);
const ffsubsync = valueAfter("--ffsubsync") || process.env.FFSUBSYNC_BIN || path.join(__dirname, ".venv/bin/ffsubsync");
const aligner = valueAfter("--aligner") || process.env.ROKU_HLS_SUBTITLE_ALIGNER || path.join(__dirname, "align-subtitles.js");

const FFMPEG_PATH_DIRS = [
  "/usr/local/bin",
  "/usr/bin",
  "/volume1/@appstore/ffmpeg7/bin",
  "/volume1/@appstore/ffmpeg/bin",
  "/volume1/@appstore/VideoStation/bin",
  "/volume1/@appstore/MediaServer/bin",
  "/volume1/@appstore/EmbyServer/bin",
];

if (!show) {
  console.error("usage: node audit-subtitle-sync.js --show \"South Park\" [--season-min 2 --season-max 3 --episode-min 6]");
  process.exit(2);
}

function valueAfter(name) {
  const inline = args.find((arg) => arg.startsWith(`${name}=`));
  if (inline) return inline.slice(name.length + 1);
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : "";
}

function normalize(value) {
  return String(value || "").toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
}

function episodeNumber(fileName) {
  const match = String(fileName || "").match(/\bS(\d{1,2})E(\d{1,3})\b/i);
  return match ? Number(match[2]) : 0;
}

function seasonNumber(fileName) {
  const match = String(fileName || "").match(/\bS(\d{1,2})E(\d{1,3})\b/i);
  return match ? Number(match[1]) : 0;
}

function findShowDir() {
  const dirs = fs.readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isDirectory());
  return dirs.find((entry) => normalize(entry.name) === normalize(show))?.name || "";
}

function videoFiles(dir) {
  return fs.readdirSync(dir)
    .filter((name) => /\.(mkv|mp4|m4v|avi|mov)$/i.test(name))
    .map((name) => path.join(dir, name));
}

function subtitleFor(video) {
  const parsed = path.parse(video);
  const candidates = [
    path.join(parsed.dir, `${parsed.name}.en.srt`),
    path.join(parsed.dir, `${parsed.name}.srt`),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
}

function runAligner(srt) {
  if (!fs.existsSync(aligner)) return { action: "skip", reason: "missing-aligner" };
  const result = spawnSync(process.execPath, [aligner, "--dry-run", srt], {
    encoding: "utf8",
    timeout: 30000,
    maxBuffer: 1024 * 1024,
  });
  const line = String(result.stdout || result.stderr || "").trim().split("\n").pop() || "";
  try {
    return JSON.parse(line);
  } catch {
    return { action: "unknown", output: line };
  }
}

function runFfsubsync(video, srt) {
  if (!fs.existsSync(ffsubsync)) return { status: "skip", reason: "missing-ffsubsync" };
  const tmp = `${srt}.audit.srt`;
  fs.rmSync(tmp, { force: true });
  const result = spawnSync(ffsubsync, [video, "-i", srt, "-o", tmp], {
    encoding: "utf8",
    env: { ...process.env, PATH: `${FFMPEG_PATH_DIRS.join(":")}:${process.env.PATH || ""}` },
    timeout: 12 * 60 * 1000,
    maxBuffer: 2 * 1024 * 1024,
  });
  fs.rmSync(tmp, { force: true });
  const output = `${result.stdout || ""}\n${result.stderr || ""}`;
  const offset = output.match(/offset seconds:\s*([-0-9.]+)/i);
  const scale = output.match(/framerate scale factor:\s*([-0-9.]+)/i);
  const score = output.match(/score:\s*([-0-9.]+)/i);
  return {
    status: result.status === 0 ? "ok" : "error",
    offsetSeconds: offset ? Number(offset[1]) : null,
    scale: scale ? Number(scale[1]) : null,
    score: score ? Number(score[1]) : null,
  };
}

const showDirName = findShowDir();
if (!showDirName) {
  console.log(JSON.stringify({ action: "error", reason: "show-not-found", root, show }));
  process.exit(1);
}

let checked = 0;
const showDir = path.join(root, showDirName);
for (let season = seasonMin; season <= seasonMax; season++) {
  const seasonDir = path.join(showDir, `Season ${String(season).padStart(2, "0")}`);
  if (!fs.existsSync(seasonDir)) {
    console.log(JSON.stringify({ action: "skip", reason: "season-missing", season, seasonDir }));
    continue;
  }
  for (const video of videoFiles(seasonDir)) {
    const ep = episodeNumber(video);
    const seasonFromName = seasonNumber(video);
    if (seasonFromName !== season || ep < episodeMin || ep > episodeMax) continue;
    const srt = subtitleFor(video);
    if (!srt) {
      console.log(JSON.stringify({ action: "missing-srt", season, episode: ep, video }));
      continue;
    }
    const anchor = runAligner(srt);
    const sync = runFfsubsync(video, srt);
    console.log(JSON.stringify({ action: "audit", show: showDirName, season, episode: ep, video, srt, anchor, sync }));
    checked++;
    if (limit > 0 && checked >= limit) process.exit(0);
  }
}
