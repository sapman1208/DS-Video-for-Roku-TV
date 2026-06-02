#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const NODE_BIN = process.env.ROKU_HLS_NODE || process.execPath;
const SUBTITLE_DOWNLOADER = process.env.ROKU_HLS_SUBTITLE_DOWNLOADER || path.join(__dirname, "download-subtitles.js");
const POLL_SECONDS = Number(process.env.ROKU_SUBTITLE_POLL_SECONDS || 900);
const LIMIT = Number((process.argv.find((arg) => arg.startsWith("--limit=")) || "").split("=")[1] || 0);
const DRY_RUN = process.argv.includes("--dry-run");
const ONCE = process.argv.includes("--once") || !process.argv.includes("--watch");
const WATCH = process.argv.includes("--watch");
const FORCE = process.argv.includes("--force");
const LOCK_FILE = process.env.ROKU_SUBTITLE_LOCK || "/tmp/roku-subtitle-watcher.lock";
const VIDEO_RE = /\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|m2v|flv|webm)$/i;
const INCLUDE_HOME = process.env.ROKU_SUBTITLE_INCLUDE_HOME === "1";
const DB_UNAVAILABLE_RE = /user VideoStation does not exist|Unknown id: VideoStation|No passwd entry|Permission denied|sudo:.*password|not in the sudoers/i;

function isSubtitleLibraryPath(filePath) {
  const norm = String(filePath || "").replace(/\\/g, "/").toLowerCase();
  if (norm.includes("/tv shows/")) return true;
  if (norm.includes("/ian's shows/")) return true;
  if (norm.includes("/ians shows/")) return true;
  if (norm.includes("/movies/")) return true;
  if (norm.includes("/new stuff/")) return true;
  if (INCLUDE_HOME && (norm.includes("/home/") || norm.includes("/home videos/"))) return true;
  return false;
}

function runSql(sql) {
  const command = `psql -U VideoStation -d video_metadata -X -q -t -A -F "\t" -c "${sql.replace(/"/g, '\\"')}"`;
  const runners = [
    ["sudo", ["-n", "-u", "VideoStation", "/bin/bash", "-lc", command]],
    ["su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command]],
  ];
  let detail = "";
  for (const [bin, args] of runners) {
    const result = spawnSync(bin, args, {
      encoding: "utf8",
    });
    if (result.status === 0) return String(result.stdout || "").trim();
    detail = (result.stderr || result.stdout || `${bin} failed ${result.status}`).trim();
    if (!DB_UNAVAILABLE_RE.test(detail)) break;
  }
  if (DB_UNAVAILABLE_RE.test(detail)) {
    console.log(JSON.stringify({ action: "subtitle-scan-skip", reason: "VideoStation database unavailable", detail }));
    return "";
  }
  throw new Error(detail);
}

function canUseVideoStationDb() {
  const result = spawnSync("id", ["VideoStation"], {
    encoding: "utf8",
  });
  return result.status === 0;
}

function subtitleTargets(filePath, lang = process.env.OPEN_SUBTITLES_LANGUAGE || process.env.OPENSUBTITLES_LANGUAGE || "en") {
  const parsed = path.parse(filePath);
  return [
    path.join(parsed.dir, `${parsed.name}.${lang}.srt`),
    path.join(parsed.dir, `${parsed.name}.srt`),
  ];
}

function hasSubtitle(filePath) {
  return subtitleTargets(filePath).some((candidate) => fs.existsSync(candidate));
}

function discoverCandidates() {
  if (!canUseVideoStationDb()) {
    console.log(JSON.stringify({ action: "subtitle-scan-skip", reason: "VideoStation user missing" }));
    return [];
  }
  const max = LIMIT > 0 ? `limit ${LIMIT}` : "";
  const rows = runSql(`
    select distinct vf.path
    from video_file vf
    where vf.path is not null
      and lower(vf.path) ~ '\\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|m2v|flv|webm)$'
    order by vf.path
    ${max}`);
  if (!rows) return [];
  return rows
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((filePath) => VIDEO_RE.test(filePath))
    .filter(isSubtitleLibraryPath)
    .filter((filePath) => FORCE || !hasSubtitle(filePath));
}

function downloadSubtitles(filePath) {
  if (!fs.existsSync(filePath)) return { action: "skip", reason: "missing", path: filePath };
  if (!FORCE && hasSubtitle(filePath)) return { action: "skip", reason: "exists", path: filePath };
  if (DRY_RUN) return { action: "would-download", path: filePath };
  if (!fs.existsSync(SUBTITLE_DOWNLOADER)) return { action: "skip", reason: "missing-downloader", path: SUBTITLE_DOWNLOADER };
  const args = [SUBTITLE_DOWNLOADER, filePath];
  if (FORCE) args.push("--force");
  const result = spawnSync(NODE_BIN, args, {
    encoding: "utf8",
    timeout: 180000,
    env: process.env,
  });
  const detail = (result.stdout || result.stderr || "").trim();
  if (/quota|allowed 5 subtitles|remaining["': -]+-?1|remaining["': -]+0/i.test(detail)) return { action: "quota", path: filePath, detail };
  if (result.status !== 0) return { action: "error", path: filePath, detail };
  return { action: hasSubtitle(filePath) ? "downloaded" : "checked", path: filePath, detail };
}

function scanOnce() {
  const candidates = discoverCandidates();
  const summary = { checked: candidates.length, downloaded: 0, skipped: 0, errors: 0 };
  console.log(JSON.stringify({ action: "subtitle-scan", candidates: candidates.length, dryRun: DRY_RUN, force: FORCE }));
  for (const filePath of candidates) {
    const result = downloadSubtitles(filePath);
    if (result.action === "downloaded" || result.action === "would-download") summary.downloaded += 1;
    else if (result.action === "error") summary.errors += 1;
    else if (result.action === "quota") {
      summary.errors += 1;
      console.log(JSON.stringify(result));
      console.log(JSON.stringify({ action: "subtitle-quota-pause" }));
      break;
    }
    else summary.skipped += 1;
    console.log(JSON.stringify(result));
  }
  console.log(JSON.stringify({ action: "subtitle-summary", ...summary }));
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
    throw new Error(`subtitle watcher already running or stale lock exists: ${LOCK_FILE}`);
  }
}

acquireLock();
do {
  scanOnce();
  if (ONCE) break;
  sleep(Math.max(60, POLL_SECONDS) * 1000);
} while (WATCH);
