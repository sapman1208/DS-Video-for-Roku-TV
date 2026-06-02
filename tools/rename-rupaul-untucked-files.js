#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const root = "/volume1/video/TV Shows/RuPaul's Drag Race All Stars Untucked";

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

for (const source of walk(root)) {
  const base = path.basename(source);
  const nextBase = base
    .replace(/RuPaul's Drag Race All Stars Untucked!/g, "RuPaul's Drag Race All Stars Untucked")
    .replace(/RuPauls\.Drag\.Race\.All\.Stars\.Untucked/g, "RuPaul's Drag Race All Stars Untucked")
    .replace(/WOWRip\.1080p-WEBRip/g, "")
    .replace(/WOWRip\.1080p/g, "")
    .replace(/\s+\./g, ".")
    .replace(/\s+/g, " ")
    .trim();
  if (base === nextBase) continue;
  const target = path.join(path.dirname(source), nextBase);
  if (fs.existsSync(target)) {
    console.log(JSON.stringify({ action: "collision", source, target }));
    continue;
  }
  fs.renameSync(source, target);
  console.log(JSON.stringify({ action: "rename", source, target }));
}
