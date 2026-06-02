#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const root = "/volume1/video/TV Shows";
const canonical = path.join(root, "RuPaul's Drag Race All Stars Untucked");
const variants = [
  path.join(root, "RuPaul's Drag Race All Stars UNTUCKED"),
  path.join(root, "RuPaul's Drag Race All Stars Untucked!"),
  path.join(root, "RuPauls Drag Race All Stars Untucked"),
];

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    out.push(full);
  }
  return out;
}

function isIgnored(item) {
  return item.split(path.sep).some((part) => part === "@eaDir") || path.basename(item) === ".DS_Store";
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function moveFile(source, target) {
  ensureDir(path.dirname(target));
  if (fs.existsSync(target)) {
    const sourceSize = fs.statSync(source).size;
    const targetSize = fs.statSync(target).size;
    if (sourceSize === targetSize) {
      fs.rmSync(source, { force: true });
      return { action: "dedupe", source, target };
    }
    return { action: "collision", source, target };
  }
  fs.renameSync(source, target);
  return { action: "move", source, target };
}

ensureDir(canonical);
const results = [];

for (const variant of variants) {
  if (!fs.existsSync(variant)) continue;
  const items = walk(variant).sort((a, b) => b.length - a.length);
  for (const item of items) {
    if (!fs.existsSync(item)) continue;
    if (isIgnored(item)) {
      fs.rmSync(item, { recursive: true, force: true });
      results.push({ action: "delete-junk", path: item });
      continue;
    }
    const stat = fs.statSync(item);
    if (stat.isDirectory()) continue;
    const rel = path.relative(variant, item);
    results.push(moveFile(item, path.join(canonical, rel)));
  }
  fs.rmSync(variant, { recursive: true, force: true });
  results.push({ action: "delete-old-folder", path: variant });
}

for (const result of results) console.log(JSON.stringify(result));
console.log(JSON.stringify({
  summary: results.reduce((acc, result) => {
    acc[result.action] = (acc[result.action] || 0) + 1;
    return acc;
  }, { canonical }),
}));
