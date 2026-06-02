#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const TRANSCODE_ROOT = process.env.ROKU_TRANSCODE_ROOT || "/volume1/video/@roku-transcodes";
const MEDIA_ROOT = process.env.ROKU_MEDIA_ROOT || "/volume1/video";
const DELETE_AFTER_COPY = process.env.ROKU_MIGRATE_DELETE_TRANSCODES !== "0";
const DRY_RUN = process.argv.includes("--dry-run");
const PRUNE_ROOT = process.argv.includes("--prune-root") || process.env.ROKU_MIGRATE_PRUNE_ROOT === "1";
const VIDEO_EXTENSIONS = new Set([".mp4"]);

function walk(dir, results = []) {
  if (!fs.existsSync(dir)) return results;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, results);
    else if (entry.isFile() && VIDEO_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) results.push(full);
  }
  return results;
}

function safeCopy(source, target) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const tmp = `${target}.tmp`;
  fs.rmSync(tmp, { force: true });
  fs.copyFileSync(source, tmp);
  fs.renameSync(tmp, target);
}

function indexFile(target) {
  const indexer = "/usr/syno/bin/synoindex";
  if (!fs.existsSync(indexer)) return;
  spawnSync(indexer, ["-a", target], { timeout: 30000 });
}

function pruneEmptyDirs(dir, stopAt) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) pruneEmptyDirs(path.join(dir, entry.name), stopAt);
  }
  if (path.resolve(dir) === path.resolve(stopAt)) return;
  try {
    fs.rmdirSync(dir);
  } catch {
    // Not empty.
  }
}

function migrateOne(source) {
  const rel = path.relative(TRANSCODE_ROOT, source);
  if (rel.startsWith("..")) return { action: "skip", reason: "outside-root", source };
  const parts = rel.split(path.sep).filter(Boolean);
  if (parts.length < 2) return { action: "skip", reason: "no-library-folder", source };
  const target = path.join(MEDIA_ROOT, ...parts);
  const sourceVsmeta = `${source}.vsmeta`;
  const targetVsmeta = `${target}.vsmeta`;
  if (fs.existsSync(target)) {
    const sameSize = fs.statSync(source).size === fs.statSync(target).size;
    if (!sameSize) return { action: "skip", reason: "target-exists-different-size", source, target };
  }
  if (DRY_RUN) return { action: "would-migrate", source, target, hasVsmeta: fs.existsSync(sourceVsmeta) };

  if (!fs.existsSync(target)) safeCopy(source, target);
  if (fs.existsSync(sourceVsmeta) && !fs.existsSync(targetVsmeta)) safeCopy(sourceVsmeta, targetVsmeta);
  indexFile(target);
  if (DELETE_AFTER_COPY) {
    fs.rmSync(source, { force: true });
    fs.rmSync(sourceVsmeta, { force: true });
  }
  return { action: "migrated", source, target, copiedVsmeta: fs.existsSync(targetVsmeta), deletedTranscode: DELETE_AFTER_COPY };
}

function main() {
  const files = walk(TRANSCODE_ROOT);
  const summary = { checked: files.length, migrated: 0, skipped: 0, errors: 0 };
  for (const file of files) {
    try {
      const result = migrateOne(file);
      if (result.action === "migrated" || result.action === "would-migrate") summary.migrated += 1;
      else summary.skipped += 1;
      console.log(JSON.stringify(result));
    } catch (err) {
      summary.errors += 1;
      console.log(JSON.stringify({ action: "error", source: file, error: err.message }));
    }
  }
  if (!DRY_RUN && DELETE_AFTER_COPY) {
    pruneEmptyDirs(TRANSCODE_ROOT, TRANSCODE_ROOT);
    if (PRUNE_ROOT) {
      try {
        fs.rmdirSync(TRANSCODE_ROOT);
      } catch {
        // Root still contains something. Leave it in place.
      }
    }
  }
  console.log(JSON.stringify({ action: "summary", ...summary, transcodeRoot: TRANSCODE_ROOT }));
}

main();
