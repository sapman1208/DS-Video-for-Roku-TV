#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
const outArg = args.find((arg) => arg.startsWith("--out="));
const outPath = outArg ? outArg.slice("--out=".length) : "/tmp/roku-normalize-plan.tsv";
const limitArg = args.find((arg) => arg.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.split("=")[1]) || 0 : 0;

const VIDEO_EXT_RE = /\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg)$/i;

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runSql(sql) {
  const command = `psql -U VideoStation -d video_metadata -X -q -t -A -F "\t" -c "${sql.replace(/"/g, '\\"')}"`;
  const result = spawnSync("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 80,
  });
  if (result.status !== 0) throw new Error((result.stderr || result.stdout || `psql failed ${result.status}`).trim());
  return String(result.stdout || "").trim();
}

function cleanPart(value) {
  return String(value || "")
    .replace(/[\\/:*?"<>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extOf(filePath) {
  const ext = path.extname(filePath);
  return VIDEO_EXT_RE.test(ext) ? ext.toLowerCase() : ext;
}

function libraryRootForPath(filePath) {
  const p = String(filePath || "").replace(/\\/g, "/");
  const known = [
    "/volume1/video/Movies",
    "/volume1/video/New Stuff",
    "/volume1/video/New stuff",
    "/volume1/video/TV Shows",
    "/volume1/video/Ian's Shows",
    "/volume1/video/Home",
  ];
  return known.find((root) => p === root || p.startsWith(`${root}/`)) || "";
}

function isSupplementalPath(filePath) {
  const parts = String(filePath || "").split("/").map((part) => part.toLowerCase());
  return parts.some((part) =>
    part === "sample" ||
    part === "samples" ||
    part === "featurette" ||
    part === "featurettes" ||
    part === "extra" ||
    part === "extras" ||
    part === "bonus" ||
    part === "behind the scenes"
  );
}

function movieTarget(row) {
  const root = libraryRootForPath(row.path) || "/volume1/video/Movies";
  const title = cleanPart(row.title || path.basename(row.path, path.extname(row.path)));
  const year = String(row.year || "").replace(/[^0-9]/g, "");
  const base = year ? `${title} (${year})` : title;
  return path.join(root, base, `${base}${extOf(row.path)}`);
}

function episodeTarget(row) {
  const root = String(row.path || "").includes("/Ian's Shows/") ? "/volume1/video/Ian's Shows" : "/volume1/video/TV Shows";
  const show = cleanPart(row.showTitle);
  const season = String(Number(row.season) || 0).padStart(2, "0");
  const episode = String(Number(row.episode) || 0).padStart(2, "0");
  const title = cleanPart(row.episodeTitle) || `Episode ${Number(row.episode) || 0}`;
  const base = `${show} - S${season}E${episode} - ${title}`;
  return path.join(root, show, `Season ${season}`, `${base}${extOf(row.path)}`);
}

function readRows(sql, mapper) {
  const output = runSql(sql);
  if (!output) return [];
  return output.split("\n").filter(Boolean).map((line) => mapper(line.split("\t")));
}

function movieRows() {
  const max = limit > 0 ? `limit ${limit}` : "";
  return readRows(`
    select vf.path, m.title, coalesce(m.year, 0)
    from video_file vf
    join movie m on m.mapper_id = vf.mapper_id
    where vf.path is not null
      and lower(vf.path) ~ '\\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg)$'
      and vf.path not like '/volume1/video/@roku-transcodes/%'
    order by vf.path
    ${max}`, (p) => ({ type: "movie", path: p[0], title: p[1], year: p[2] }));
}

function episodeRows() {
  const max = limit > 0 ? `limit ${limit}` : "";
  return readRows(`
    select vf.path, t.title, e.season, e.episode, e.tag_line
    from video_file vf
    join tvshow_episode e on e.mapper_id = vf.mapper_id
    join tvshow t on t.id = e.tvshow_id
    where vf.path is not null
      and lower(vf.path) ~ '\\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg)$'
      and vf.path not like '/volume1/video/@roku-transcodes/%'
    order by vf.path
    ${max}`, (p) => ({ type: "episode", path: p[0], showTitle: p[1], season: p[2], episode: p[3], episodeTitle: p[4] }));
}

function planRows() {
  const rows = [...movieRows(), ...episodeRows()];
  const seenTargets = new Map();
  return rows.map((row) => {
    const target = row.type === "movie" ? movieTarget(row) : episodeTarget(row);
    const normalized = path.normalize(row.path) === path.normalize(target);
    const exists = fs.existsSync(target) && path.normalize(row.path) !== path.normalize(target);
    const prior = seenTargets.get(target);
    seenTargets.set(target, row.path);
    let status = normalized ? "ok" : "move";
    if (!libraryRootForPath(row.path)) status = "review-no-library-root";
    if (isSupplementalPath(row.path)) status = "review-supplemental";
    if (exists) status = "review-target-exists";
    if (prior) status = "review-collision";
    return { status, type: row.type, source: row.path, target };
  });
}

const rows = planRows();
const lines = [
  ["status", "type", "source", "target"].join("\t"),
  ...rows.map((r) => [r.status, r.type, r.source, r.target].join("\t")),
];
fs.writeFileSync(outPath, `${lines.join("\n")}\n`);

const summary = rows.reduce((acc, row) => {
  acc[row.status] = (acc[row.status] || 0) + 1;
  return acc;
}, { total: rows.length });
console.log(JSON.stringify({ outPath, summary }, null, 2));
