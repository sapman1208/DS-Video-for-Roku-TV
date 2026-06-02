#!/usr/bin/env node
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ffmpeg = "/var/packages/ffmpeg7/target/bin/ffmpeg";
const oldDir = "/volume1/video/Movies/Titanic_Versión_Extendida_Extended_Cut_BDRemux.1080p.DTS-MA.ENGaudioSPAsubs_by.Suncool";
const oldFile = path.join(oldDir, "Titanic_Versión_Extendida_Extended_Cut_BDRemux.1080p.DTS-MA.ENGaudioSPAsubs.m2ts");
const newDir = "/volume1/video/Movies/Titanic Extended Cut (1997)";
const newFile = path.join(newDir, "Titanic Extended Cut (1997).m2ts");
const poster = path.join(newDir, "Titanic Extended Cut (1997).jpg");

function varint(num) {
  let value = Math.max(0, Number(num) || 0);
  const out = [];
  do {
    let byte = value & 0x7f;
    value = Math.floor(value / 128);
    if (value !== 0) byte |= 0x80;
    out.push(byte);
  } while (value !== 0);
  return Buffer.from(out);
}

function tag(tagByte, value, kind = "string") {
  const t = Buffer.from([tagByte]);
  if (kind === "int") return Buffer.concat([t, varint(value)]);
  if (kind === "bool") return Buffer.concat([t, Buffer.from([value ? 1 : 0])]);
  if (kind === "date") return Buffer.concat([t, Buffer.from([0x0a]), Buffer.from(value, "utf8")]);
  if (kind === "content") return Buffer.concat([t, varint(value.length), value]);
  const bytes = Buffer.from(String(value || ""), "utf8");
  return Buffer.concat([t, varint(bytes.length), bytes]);
}

function imageTags(file) {
  if (!fs.existsSync(file)) return [];
  const data = fs.readFileSync(file);
  const b64 = data.toString("base64").replace(/.{76}/g, "$&\n");
  const md5 = crypto.createHash("md5").update(data).digest("hex");
  return [
    Buffer.from([0x8a]),
    tag(0x01, b64),
    Buffer.from([0x92]),
    tag(0x01, md5),
  ];
}

fs.mkdirSync(newDir, { recursive: true });
if (!fs.existsSync(oldFile) && !fs.existsSync(newFile)) {
  throw new Error(`missing source ${oldFile}`);
}
if (!fs.existsSync(newFile)) fs.renameSync(oldFile, newFile);

if (!fs.existsSync(poster) && fs.existsSync(ffmpeg)) {
  const result = spawnSync(ffmpeg, [
    "-y",
    "-ss", "00:10:00",
    "-i", newFile,
    "-frames:v", "1",
    "-vf", "scale=600:-2,drawbox=y=ih-96:color=black@0.65:width=iw:height=96:t=fill,drawtext=text='EXTENDED CUT':fontcolor=white:fontsize=46:x=(w-text_w)/2:y=h-72",
    poster,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    const fallback = spawnSync(ffmpeg, ["-y", "-ss", "00:10:00", "-i", newFile, "-frames:v", "1", "-vf", "scale=600:-2", poster], { encoding: "utf8" });
    if (fallback.status !== 0) console.error(fallback.stderr || result.stderr);
  }
}

const title = "Titanic Extended Cut";
const summary = "Extended cut version of Titanic, stored as a separate entry from the theatrical release.";
const chunks = [
  Buffer.from([0x08, 0x01]),
  tag(0x12, title),
  tag(0x1a, title),
  tag(0x22, "Extended Cut"),
  tag(0x28, 1997, "int"),
  tag(0x32, "1997-12-19", "date"),
  tag(0x38, true, "bool"),
  tag(0x42, summary),
  ...imageTags(poster),
];
fs.writeFileSync(`${newFile}.vsmeta`, Buffer.concat(chunks));

try {
  fs.rmSync(oldDir, { recursive: true, force: true });
} catch {
  // Best effort cleanup.
}

console.log(JSON.stringify({ newFile, vsmeta: `${newFile}.vsmeta`, poster, posterExists: fs.existsSync(poster) }, null, 2));
