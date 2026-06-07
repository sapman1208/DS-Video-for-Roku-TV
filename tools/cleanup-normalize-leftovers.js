#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const planArg = args.find((arg) => arg.startsWith("--plan="));
const logArg = args.find((arg) => arg.startsWith("--log="));
const planPath = planArg ? planArg.slice("--plan=".length) : "/tmp/roku-normalize-plan.tsv";
const logPath = logArg ? logArg.slice("--log=".length) : "/tmp/roku-normalize-apply.log";

const LIBRARY_ROOTS = [
  "/volume1/video/Movies",
  "/volume1/video/New Stuff",
  "/volume1/video/New stuff",
  "/volume1/video/TV Shows",
  "/volume1/video/Ian's Shows",
];

const VIDEO_EXT_RE = /\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg)$/i;
const JUNK_EXT_RE = /\.(nfo|txt|url|jpg|jpeg|png|sfv|md5|srt|sub|idx|ass|ssa|log|ini|db)$/i;
const JUNK_NAMES = new Set([
  "@eadir",
  "sample",
  "samples",
  "featurette",
  "featurettes",
  "extra",
  "extras",
  "screens",
  "screenshot",
  "screenshots",
  "proof",
  "subs",
  "subtitles",
  "__macosx",
]);

function parsePlanLine(line) {
  const [status, type, source, target] = line.split("\t");
  return { status, type, source, target };
}

function readPlan() {
  if (!fs.existsSync(planPath)) return [];
  return fs.readFileSync(planPath, "utf8").split("\n").filter(Boolean).slice(1).map(parsePlanLine);
}

function readMovedSources() {
  if (!fs.existsSync(logPath)) return new Set();
  const sources = new Set();
  for (const line of fs.readFileSync(logPath, "utf8").split("\n")) {
    if (!line || line[0] !== "{") continue;
    try {
      const entry = JSON.parse(line);
      if ((entry.action === "move" || entry.action === "move-sidecar") && entry.source) {
        sources.add(entry.source);
      }
    } catch {
      // Ignore non-JSON lines.
    }
  }
  return sources;
}

function isInsideLibrary(filePath) {
  const normalized = path.normalize(filePath);
  return LIBRARY_ROOTS.some((root) => normalized === root || normalized.startsWith(`${root}/`));
}

function isJunkPath(filePath) {
  const parts = path.normalize(filePath).split(path.sep).map((part) => part.toLowerCase());
  return parts.some((part) => JUNK_NAMES.has(part)) || JUNK_EXT_RE.test(filePath);
}

function safeRm(filePath) {
  if (!isInsideLibrary(filePath)) return false;
  if (!fs.existsSync(filePath)) return false;
  if (apply) fs.rmSync(filePath, { recursive: true, force: true });
  return true;
}

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    out.push(full);
  }
  return out;
}

function hasVideoDescendant(dir) {
  if (!fs.existsSync(dir)) return false;
  for (const item of walk(dir, [])) {
    try {
      if (fs.statSync(item).isFile() && VIDEO_EXT_RE.test(item)) return true;
    } catch {
      // Ignore disappearing files.
    }
  }
  return false;
}

function pruneEmptyDirs(root) {
  const dirs = walk(root, []).filter((item) => {
    try {
      return fs.statSync(item).isDirectory();
    } catch {
      return false;
    }
  }).sort((a, b) => b.length - a.length);
  let count = 0;
  for (const dir of dirs) {
    if (LIBRARY_ROOTS.includes(path.normalize(dir))) continue;
    try {
      const entries = fs.readdirSync(dir).filter((name) => name !== ".DS_Store");
      if (entries.length === 0) {
        if (apply) fs.rmSync(dir, { recursive: true, force: true });
        count += 1;
      }
    } catch {
      // Ignore.
    }
  }
  return count;
}

const planRows = readPlan();
const movedSources = readMovedSources();
const deleteFiles = new Set();
const candidateDirs = new Set();

for (const row of planRows) {
  if (!row.source || !isInsideLibrary(row.source)) continue;
  if (movedSources.has(row.source)) {
    candidateDirs.add(path.dirname(row.source));
    continue;
  }

  if (row.status.startsWith("review-")) {
    deleteFiles.add(row.source);
    deleteFiles.add(`${row.source}.vsmeta`);
    candidateDirs.add(path.dirname(row.source));
  }
}

for (const dir of Array.from(candidateDirs)) {
  if (!fs.existsSync(dir) || !isInsideLibrary(dir)) continue;
  if (!hasVideoDescendant(dir)) {
    for (const item of walk(dir, [])) {
      if (fs.existsSync(item)) deleteFiles.add(item);
    }
    deleteFiles.add(dir);
  } else {
    for (const item of walk(dir, [])) {
      try {
        if (fs.statSync(item).isFile() && isJunkPath(item)) deleteFiles.add(item);
      } catch {
        // Ignore.
      }
    }
  }
}

const sorted = Array.from(deleteFiles).sort((a, b) => b.length - a.length);
let deleted = 0;
for (const item of sorted) {
  try {
    if (safeRm(item)) {
      deleted += 1;
      console.log(JSON.stringify({ action: apply ? "delete" : "would-delete", path: item }));
    }
  } catch (err) {
    console.log(JSON.stringify({ action: "error", path: item, error: err.message }));
  }
}

let pruned = 0;
for (const root of LIBRARY_ROOTS) {
  pruned += pruneEmptyDirs(root);
}

console.log(JSON.stringify({
  summary: {
    deleteCandidates: sorted.length,
    deleted,
    prunedEmptyDirs: pruned,
  },
  apply,
}));
