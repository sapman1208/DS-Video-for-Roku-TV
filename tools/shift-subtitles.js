#!/usr/bin/env node
const fs = require("fs");

const args = process.argv.slice(2);
const secondsArg = args.find((arg) => arg === "--seconds" || arg === "-s");
const secondsIndex = secondsArg ? args.indexOf(secondsArg) : -1;
const seconds = secondsIndex >= 0 ? Number(args[secondsIndex + 1]) : Number(args[0]);
const files = secondsIndex >= 0 ? args.slice(secondsIndex + 2) : args.slice(1);

if (!Number.isFinite(seconds) || files.length === 0) {
  console.error("usage: node shift-subtitles.js --seconds -3 /path/file.srt [...]");
  process.exit(2);
}

const offsetMs = Math.round(seconds * 1000);
const timeRe = /(\d{2}):(\d{2}):(\d{2}),(\d{3})/g;

function parseTime(match, hh, mm, ss, ms) {
  return (((Number(hh) * 60 + Number(mm)) * 60 + Number(ss)) * 1000) + Number(ms);
}

function formatTime(totalMs) {
  const clamped = Math.max(0, totalMs);
  const ms = clamped % 1000;
  const totalSeconds = Math.floor(clamped / 1000);
  const ss = totalSeconds % 60;
  const totalMinutes = Math.floor(totalSeconds / 60);
  const mm = totalMinutes % 60;
  const hh = Math.floor(totalMinutes / 60);
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:${String(ss).padStart(2, "0")},${String(ms).padStart(3, "0")}`;
}

for (const file of files) {
  if (!fs.existsSync(file)) {
    console.log(`[shift-srt] missing ${file}`);
    continue;
  }

  const input = fs.readFileSync(file, "utf8");
  const output = input.replace(timeRe, (match, hh, mm, ss, ms) => formatTime(parseTime(match, hh, mm, ss, ms) + offsetMs));
  if (output === input) {
    console.log(`[shift-srt] unchanged ${file}`);
    continue;
  }

  fs.writeFileSync(`${file}.bak`, input);
  fs.writeFileSync(file, output);
  console.log(`[shift-srt] shifted ${seconds}s ${file}`);
}
