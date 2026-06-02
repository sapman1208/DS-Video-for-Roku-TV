#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const FFMPEG = process.env.FFMPEG || "/var/packages/ffmpeg7/target/bin/ffmpeg";
const NODE_BIN = process.env.ROKU_HLS_NODE || process.execPath;
const VSMETA_GENERATOR = process.env.ROKU_HLS_VSMETA_GENERATOR || path.join(__dirname, "generate-vsmeta.js");
const DRY_RUN = process.argv.includes("--dry-run");
const FORCE = process.argv.includes("--force");
const showArg = process.argv.find((arg) => arg.startsWith("--show="));
const SHOW_FILTER = showArg ? showArg.slice("--show=".length) : "";

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

function videoRows() {
  const where = SHOW_FILTER
    ? `where lower(t.title) like lower('%${sqlEscape(SHOW_FILTER)}%')`
    : "";
  const rows = runSql(`
    select t.title, e.season, e.episode, coalesce(e.tag_line, ''), vf.path
    from tvshow t
    join tvshow_episode e on e.tvshow_id = t.id
    join video_file vf on vf.mapper_id = e.mapper_id
    ${where}
    order by t.title, e.season, e.episode, vf.path`);
  if (!rows) return [];
  return rows.split("\n").map((line) => {
    const parts = line.split("\t");
    return {
      show: parts[0] || "",
      season: Number(parts[1]) || 0,
      episode: Number(parts[2]) || 0,
      title: parts[3] || "",
      path: parts.slice(4).join("\t"),
    };
  }).filter((row) => row.path);
}

function posterPaths(videoPath) {
  const dir = path.dirname(videoPath);
  const base = path.basename(videoPath);
  const thumbDir = path.join(dir, "@eaDir", base);
  return {
    dir: thumbDir,
    poster: path.join(thumbDir, "SYNOVIDEO_VIDEO_POSTER.jpg"),
    posterThumb: path.join(thumbDir, "SYNOVIDEO_VIDEO_POSTER_JPEGTN.jpg"),
    screenshot: path.join(thumbDir, "SYNOVIDEO_VIDEO_SCREENSHOT.jpg"),
    screenshotThumb: path.join(thumbDir, "SYNOVIDEO_VIDEO_SCREENSHOT_JPEGTN.jpg"),
  };
}

function hasPoster(videoPath) {
  const paths = posterPaths(videoPath);
  return fs.existsSync(paths.poster) || fs.existsSync(paths.posterThumb) || fs.existsSync(paths.screenshot) || fs.existsSync(paths.screenshotThumb);
}

function generateStill(videoPath) {
  const paths = posterPaths(videoPath);
  if (!FORCE && hasPoster(videoPath)) return { action: "skip", reason: "poster-exists", path: videoPath };
  if (DRY_RUN) return { action: "would-generate", path: videoPath, output: paths.poster };

  fs.mkdirSync(paths.dir, { recursive: true });
  const tmp = `${paths.poster}.tmp.jpg`;
  fs.rmSync(tmp, { force: true });
  const result = spawnSync(FFMPEG, [
    "-hide_banner",
    "-loglevel", "warning",
    "-y",
    "-ss", "00:03:00",
    "-i", videoPath,
    "-frames:v", "1",
    "-vf", "scale=640:-2",
    tmp,
  ], { encoding: "utf8", timeout: 120000 });
  if (result.status !== 0 || !fs.existsSync(tmp)) {
    fs.rmSync(tmp, { force: true });
    return { action: "error", path: videoPath, error: (result.stderr || result.stdout || `ffmpeg exited ${result.status}`).trim().slice(0, 500) };
  }
  fs.renameSync(tmp, paths.poster);
  fs.copyFileSync(paths.poster, paths.posterThumb);
  fs.copyFileSync(paths.poster, paths.screenshot);
  fs.copyFileSync(paths.poster, paths.screenshotThumb);
  return { action: "generated", path: videoPath, output: paths.poster };
}

function regenerateVsmeta(videoPath) {
  if (DRY_RUN || !fs.existsSync(VSMETA_GENERATOR)) return false;
  const result = spawnSync(NODE_BIN, [VSMETA_GENERATOR, "--force", videoPath, videoPath], {
    encoding: "utf8",
    timeout: 120000,
  });
  return result.status === 0;
}

const rows = videoRows();
const summary = { checked: rows.length, generated: 0, skipped: 0, errors: 0, vsmeta: 0 };
for (const row of rows) {
  if (!fs.existsSync(row.path)) {
    console.log(JSON.stringify({ action: "skip", reason: "missing-video", ...row }));
    summary.skipped += 1;
    continue;
  }
  const result = generateStill(row.path);
  if (result.action === "generated" || result.action === "would-generate") summary.generated += 1;
  else if (result.action === "error") summary.errors += 1;
  else summary.skipped += 1;
  if (result.action === "generated" || (result.action === "skip" && result.reason === "poster-exists")) {
    if (regenerateVsmeta(row.path)) summary.vsmeta += 1;
  }
  console.log(JSON.stringify({ ...result, show: row.show, season: row.season, episode: row.episode, title: row.title }));
}
console.log(JSON.stringify({ action: "summary", ...summary, showFilter: SHOW_FILTER }));
