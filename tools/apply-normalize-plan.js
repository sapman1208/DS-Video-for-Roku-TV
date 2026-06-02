#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const planArg = args.find((arg) => arg.startsWith("--plan="));
const dryRun = args.includes("--dry-run");
const planPath = planArg ? planArg.slice("--plan=".length) : "/tmp/roku-normalize-plan.tsv";

function parseLine(line) {
  const [status, type, source, target] = line.split("\t");
  return { status, type, source, target };
}

function moveFile(source, target) {
  if (!fs.existsSync(source)) return { moved: false, reason: "source-missing" };
  if (fs.existsSync(target)) return { moved: false, reason: "target-exists" };
  if (!dryRun) {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.renameSync(source, target);
  }
  return { moved: true };
}

function sidecarsFor(source, target) {
  return [
    [`${source}.vsmeta`, `${target}.vsmeta`],
    [`${source}.srt`, `${target}.srt`],
    [`${source}.en.srt`, `${target}.en.srt`],
  ];
}

const raw = fs.readFileSync(planPath, "utf8").split("\n").filter(Boolean);
const rows = raw.slice(1).map(parseLine);
const summary = { total: rows.length, moved: 0, skipped: 0, sidecars: 0, errors: 0 };

for (const row of rows) {
  if (row.status !== "move") {
    summary.skipped += 1;
    continue;
  }

  try {
    const result = moveFile(row.source, row.target);
    if (!result.moved) {
      summary.skipped += 1;
      console.log(JSON.stringify({ action: "skip", reason: result.reason, source: row.source, target: row.target }));
      continue;
    }
    summary.moved += 1;
    console.log(JSON.stringify({ action: dryRun ? "would-move" : "move", type: row.type, source: row.source, target: row.target }));

    for (const [sideSource, sideTarget] of sidecarsFor(row.source, row.target)) {
      const sideResult = moveFile(sideSource, sideTarget);
      if (sideResult.moved) {
        summary.sidecars += 1;
        console.log(JSON.stringify({ action: dryRun ? "would-move-sidecar" : "move-sidecar", source: sideSource, target: sideTarget }));
      }
    }
  } catch (err) {
    summary.errors += 1;
    console.log(JSON.stringify({ action: "error", source: row.source, target: row.target, error: err.message }));
  }
}

console.log(JSON.stringify({ summary, dryRun }));
