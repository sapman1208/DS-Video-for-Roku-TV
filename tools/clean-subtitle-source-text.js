#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const roots = args.filter((arg) => !arg.startsWith("--"));

if (roots.length === 0) {
  console.error("usage: node clean-subtitle-source-text.js [--dry-run] /path/file-or-directory [...]");
  process.exit(2);
}

function isSubtitleSourceCreditLine(line) {
  const text = String(line || "")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
  if (!text) return false;
  if (/tvsubtitles\.net|opensubtitles\.(org|com)|subdl\.com|addic7ed\.com|podnapisi\.net|subscene\.|isubtitles\.org|subtitles\.net/.test(text)) return true;
  if (/(www\.|https?:\/\/).*(subtitles?|subs?|caption|opensubtitles|tvsubtitles|subdl|addic7ed|podnapisi)/.test(text)) return true;
  if (/(downloaded|provided|synced|corrected|captioned)\s+(from|by)/.test(text) && /(subtitles?|subs?|caption|www\.|https?:\/\/)/.test(text)) return true;
  if (/^(subtitles?|subs?|captions?)\s+(by|from|downloaded)/.test(text)) return true;
  return false;
}

function cleanSrt(filePath) {
  const input = fs.readFileSync(filePath, "utf8");
  const blocks = input
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter(Boolean);
  const kept = [];
  let removedLines = 0;
  let removedBlocks = 0;
  for (const block of blocks) {
    const lines = block.split("\n");
    if (/^\d+$/.test(lines[0] || "")) lines.shift();
    const timing = lines.shift() || "";
    if (!timing.includes("-->")) {
      kept.push(block);
      continue;
    }
    const textLines = [];
    for (const line of lines) {
      if (isSubtitleSourceCreditLine(line)) removedLines += 1;
      else textLines.push(line);
    }
    if (textLines.length === 0) {
      removedBlocks += 1;
      continue;
    }
    kept.push({ timing, textLines });
  }
  if (removedLines === 0 && removedBlocks === 0) return null;
  const rendered = kept.map((block, index) => {
    if (typeof block === "string") return block;
    return [String(index + 1), block.timing, ...block.textLines].join("\n");
  }).join("\n\n") + "\n";
  if (!dryRun) fs.writeFileSync(filePath, rendered);
  return { file: filePath, removedLines, removedBlocks };
}

function walk(target) {
  if (!fs.existsSync(target)) return [];
  const stat = fs.statSync(target);
  if (stat.isFile()) return /\.srt$/i.test(target) ? [target] : [];
  if (!stat.isDirectory()) return [];
  const found = [];
  for (const entry of fs.readdirSync(target, { withFileTypes: true })) {
    if (entry.name === "@eaDir" || entry.name.startsWith(".")) continue;
    found.push(...walk(path.join(target, entry.name)));
  }
  return found;
}

let checked = 0;
let changed = 0;
let removedLines = 0;
let removedBlocks = 0;
for (const root of roots) {
  for (const file of walk(root)) {
    checked += 1;
    const result = cleanSrt(file);
    if (!result) continue;
    changed += 1;
    removedLines += result.removedLines;
    removedBlocks += result.removedBlocks;
    console.log(JSON.stringify({ action: dryRun ? "would-clean" : "cleaned", ...result }));
  }
}
console.log(JSON.stringify({ action: "summary", dryRun, checked, changed, removedLines, removedBlocks }));
