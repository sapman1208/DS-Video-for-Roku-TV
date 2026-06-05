#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const file = args.find((arg) => !arg.startsWith("--")) || "";
const anchorsArg = args.find((arg) => arg.startsWith("--anchors="));
const anchorsPath = anchorsArg ? anchorsArg.slice("--anchors=".length) : path.join(__dirname, "subtitle-anchors.json");
const dryRun = args.includes("--dry-run");
const maxShiftArg = args.find((arg) => arg.startsWith("--max-shift="));
const maxShiftMs = Math.round((maxShiftArg ? Number(maxShiftArg.slice("--max-shift=".length)) : 120) * 1000);

if (!file) {
  console.error("usage: node align-subtitles.js [--dry-run] [--anchors=subtitle-anchors.json] /path/video.en.srt");
  process.exit(2);
}

function cleanNamePart(value) {
  return String(value || "")
    .replace(/[\\/:*?"<>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalize(value) {
  return cleanNamePart(value)
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function withoutKnownExtensions(value) {
  return String(value || "")
    .replace(/\.(en|eng|srt|vtt)$/i, "")
    .replace(/\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|webm)$/i, "");
}

function parseInfo(filePath) {
  const parts = String(filePath || "").replace(/\\/g, "/").split("/").filter(Boolean);
  const fileName = parts[parts.length - 1] || "";
  const base = withoutKnownExtensions(fileName).replace(/[._]+/g, " ");
  const match = base.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || base.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  if (!match) return null;
  const libraryIndex = parts.findIndex((part) => normalize(part) === "tv shows" || normalize(part) === "ians shows");
  const show = libraryIndex >= 0 ? cleanNamePart(parts[libraryIndex + 1] || "") : cleanNamePart(base.slice(0, match.index));
  return { show, season: Number(match[1]) || 0, episode: Number(match[2]) || 0 };
}

function parseTime(value) {
  const match = String(value || "").match(/(\d{2}):(\d{2}):(\d{2}),(\d{3})/);
  if (!match) return NaN;
  return (((Number(match[1]) * 60 + Number(match[2])) * 60 + Number(match[3])) * 1000) + Number(match[4]);
}

function formatTime(totalMs) {
  const clamped = Math.max(0, Math.round(totalMs));
  const ms = clamped % 1000;
  const totalSeconds = Math.floor(clamped / 1000);
  const ss = totalSeconds % 60;
  const totalMinutes = Math.floor(totalSeconds / 60);
  const mm = totalMinutes % 60;
  const hh = Math.floor(totalMinutes / 60);
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:${String(ss).padStart(2, "0")},${String(ms).padStart(3, "0")}`;
}

function parseCues(input) {
  const blocks = input.replace(/\r/g, "").split(/\n{2,}/);
  const cues = [];
  for (const block of blocks) {
    const lines = block.split("\n").filter(Boolean);
    const timeIndex = lines.findIndex((line) => line.includes("-->"));
    if (timeIndex < 0) continue;
    const start = parseTime(lines[timeIndex].split("-->")[0]);
    if (!Number.isFinite(start)) continue;
    cues.push({
      start,
      text: lines.slice(timeIndex + 1).join(" "),
    });
  }
  return cues;
}

function shiftSrt(input, offsetMs) {
  return input.replace(/(\d{2}):(\d{2}):(\d{2}),(\d{3})/g, (match) => formatTime(parseTime(match) + offsetMs));
}

function remapSrt(input, scale, offsetMs) {
  return input.replace(/(\d{2}):(\d{2}):(\d{2}),(\d{3})/g, (match) => formatTime((parseTime(match) * scale) + offsetMs));
}

function loadAnchors() {
  if (!fs.existsSync(anchorsPath)) return {};
  return JSON.parse(fs.readFileSync(anchorsPath, "utf8"));
}

const info = parseInfo(file);
if (!info) {
  console.log(JSON.stringify({ action: "skip", reason: "unparsed", file }));
  process.exit(0);
}

const anchors = loadAnchors();
const key = `${normalize(info.show)}|${info.season}|${info.episode}`;
const episodeAnchors = anchors[key] || [];
if (episodeAnchors.length === 0) {
  console.log(JSON.stringify({ action: "skip", reason: "no-anchor", key, file }));
  process.exit(0);
}

if (!fs.existsSync(file)) {
  console.log(JSON.stringify({ action: "skip", reason: "missing-file", file }));
  process.exit(0);
}

const input = fs.readFileSync(file, "utf8");
const cues = parseCues(input);
const matches = [];
for (const anchor of episodeAnchors) {
  const needle = normalize(anchor.text);
  const cue = cues.find((item) => normalize(item.text).includes(needle));
  const targetMs = parseTime(anchor.time);
  if (cue && Number.isFinite(targetMs)) {
    matches.push({ anchor, cue, offsetMs: targetMs - cue.start });
  }
}

if (matches.length === 0) {
  console.log(JSON.stringify({ action: "skip", reason: "anchor-not-found", key, file }));
  process.exit(0);
}

if (matches.length >= 2) {
  matches.sort((a, b) => a.cue.start - b.cue.start);
  const first = matches[0];
  const last = matches[matches.length - 1];
  const sourceSpan = last.cue.start - first.cue.start;
  const targetSpan = parseTime(last.anchor.time) - parseTime(first.anchor.time);
  if (sourceSpan < 10000 || targetSpan < 10000) {
    console.log(JSON.stringify({ action: "skip", reason: "anchor-span-too-short", key, file }));
    process.exit(0);
  }
  const scale = targetSpan / sourceSpan;
  const offsetMs = parseTime(first.anchor.time) - (first.cue.start * scale);
  if (scale < 0.97 || scale > 1.03 || Math.abs(offsetMs) > maxShiftMs) {
    console.log(JSON.stringify({ action: "skip", reason: "remap-too-large", key, file, scale, offsetSeconds: offsetMs / 1000 }));
    process.exit(0);
  }
  const residuals = matches.map((item) => Math.abs(((item.cue.start * scale) + offsetMs) - parseTime(item.anchor.time)));
  const maxResidualMs = Math.max(...residuals);
  if (maxResidualMs > 1500) {
    console.log(JSON.stringify({ action: "skip", reason: "anchor-residual-too-large", key, file, scale, maxResidualSeconds: maxResidualMs / 1000 }));
    process.exit(0);
  }
  if (Math.abs(scale - 1) < 0.0001 && Math.abs(offsetMs) < 250) {
    console.log(JSON.stringify({ action: "ok", key, file, mode: "linear", offsetSeconds: 0, scale: 1 }));
    process.exit(0);
  }
  if (!dryRun) fs.writeFileSync(file, remapSrt(input, scale, offsetMs));
  console.log(JSON.stringify({
    action: dryRun ? "would-align" : "aligned",
    key,
    file,
    mode: "linear",
    anchors: matches.length,
    scale,
    offsetSeconds: Math.round(offsetMs) / 1000,
    maxResidualSeconds: Math.round(maxResidualMs) / 1000,
  }));
  process.exit(0);
}

const match = matches[0];
if (Math.abs(match.offsetMs) > maxShiftMs) {
  console.log(JSON.stringify({ action: "skip", reason: "shift-too-large", key, file, offsetSeconds: match.offsetMs / 1000 }));
  process.exit(0);
}
if (Math.abs(match.offsetMs) < 250) {
  console.log(JSON.stringify({ action: "ok", key, file, mode: "shift", offsetSeconds: 0 }));
  process.exit(0);
}

if (!dryRun) fs.writeFileSync(file, shiftSrt(input, match.offsetMs));
console.log(JSON.stringify({
  action: dryRun ? "would-align" : "aligned",
  key,
  file,
  mode: "shift",
  text: match.anchor.text,
  cueTime: formatTime(match.cue.start),
  targetTime: match.anchor.time,
  offsetSeconds: Math.round(match.offsetMs) / 1000,
}));
