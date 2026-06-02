#!/usr/bin/env node
const fs = require("fs");
const https = require("https");
const path = require("path");

const API_KEY = process.env.OPEN_SUBTITLES_API_KEY || process.env.OPENSUBTITLES_API_KEY || "";
const USERNAME = process.env.OPEN_SUBTITLES_USERNAME || process.env.OPENSUBTITLES_USERNAME || "";
const PASSWORD = process.env.OPEN_SUBTITLES_PASSWORD || process.env.OPENSUBTITLES_PASSWORD || "";
const LANGUAGE = process.env.OPEN_SUBTITLES_LANGUAGE || "en";
const USER_AGENT = process.env.OPEN_SUBTITLES_USER_AGENT || "RokuDSVideo v1.0";
const BASE_URL = "https://api.opensubtitles.com/api/v1";

const target = process.argv.slice(2).find((arg) => !arg.startsWith("--"));
const FORCE = process.argv.includes("--force");

if (!target) {
  console.error("usage: OPEN_SUBTITLES_API_KEY=... node download-subtitles.js /path/video.mp4");
  process.exit(2);
}
if (!API_KEY) {
  console.log("[subs] skipped missing api key");
  process.exit(0);
}
if (!fs.existsSync(target)) {
  console.log(`[subs] skipped missing file ${target}`);
  process.exit(0);
}

function cleanNamePart(value) {
  return String(value || "")
    .replace(/[\\/:*?"<>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function withoutVideoExtension(value) {
  return String(value || "").replace(/\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|m2v|flv|webm)$/i, "");
}

function libraryNameForPart(part) {
  const norm = cleanNamePart(part).toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
  if (norm === "tv shows") return "TV Shows";
  if (norm === "ians shows") return "Ian's Shows";
  if (norm === "movies" || norm === "movie") return "Movies";
  if (norm === "new stuff") return "New Stuff";
  return "";
}

function parseVideoInfo(filePath) {
  const parts = String(filePath || "").replace(/\\/g, "/").split("/").filter(Boolean);
  const fileName = parts[parts.length - 1] || "";
  const base = withoutVideoExtension(fileName).replace(/[._]+/g, " ");
  const episodeMatch = base.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || base.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  const libraryIndex = parts.findIndex((part) => libraryNameForPart(part));
  const library = libraryIndex >= 0 ? libraryNameForPart(parts[libraryIndex]) : "";
  if (episodeMatch && (library === "TV Shows" || library === "Ian's Shows")) {
    const show = cleanNamePart(parts[libraryIndex + 1] || base.slice(0, episodeMatch.index));
    return {
      type: "episode",
      query: show,
      season: Number(episodeMatch[1]),
      episode: Number(episodeMatch[2]),
    };
  }
  let title = base;
  const yearMatch = title.match(/\b(19\d{2}|20\d{2})\b/);
  const year = yearMatch ? Number(yearMatch[1]) : 0;
  if (yearMatch) title = title.slice(0, yearMatch.index);
  title = cleanNamePart(title.replace(/\b(2160p|1080p|720p|480p|web[-_. ]?dl|webrip|hdtv|bdrip|bluray|x264|x265|h264|h265|aac|dts)\b.*$/i, ""));
  return { type: "movie", query: title || cleanNamePart(base), year };
}

function subtitleTargets(filePath) {
  const parsed = path.parse(filePath);
  return [
    path.join(parsed.dir, `${parsed.name}.${LANGUAGE}.srt`),
    path.join(parsed.dir, `${parsed.name}.srt`),
  ];
}

function canonicalQueryValue(value) {
  return cleanNamePart(value).toLowerCase();
}

function hasSubtitle(filePath) {
  return subtitleTargets(filePath).some((candidate) => fs.existsSync(candidate));
}

function requestJson(method, endpoint, body, token = "", redirectCount = 0) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : "";
    const targetUrl = /^https?:\/\//i.test(endpoint) ? endpoint : `${BASE_URL}${endpoint}`;
    const req = https.request(targetUrl, {
      method,
      headers: {
        "Api-Key": API_KEY,
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
        "Content-Type": "application/json",
        ...(payload ? { "Content-Length": Buffer.byteLength(payload) } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirectCount < 5) {
          const next = new URL(res.headers.location, targetUrl);
          return requestJson(method, next.href, body, token, redirectCount + 1)
            .then(resolve)
            .catch(reject);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) return reject(new Error(`${res.statusCode} ${text.slice(0, 200)}`));
        try {
          resolve(JSON.parse(text || "{}"));
        } catch (err) {
          reject(err);
        }
      });
    });
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function downloadFile(url, filePath, redirectCount = 0) {
  return new Promise((resolve, reject) => {
    const tmp = `${filePath}.tmp`;
    fs.rmSync(tmp, { force: true });
    const out = fs.createWriteStream(tmp);
    https.get(url, { headers: { "User-Agent": USER_AGENT } }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirectCount < 5) {
        out.close(() => fs.rmSync(tmp, { force: true }));
        const next = new URL(res.headers.location, url).href;
        return downloadFile(next, filePath, redirectCount + 1).then(resolve).catch(reject);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        out.close(() => fs.rmSync(tmp, { force: true }));
        return reject(new Error(`download ${res.statusCode}`));
      }
      res.pipe(out);
      out.on("finish", () => {
        out.close(() => {
          fs.renameSync(tmp, filePath);
          resolve();
        });
      });
    }).on("error", (err) => {
      out.close(() => fs.rmSync(tmp, { force: true }));
      reject(err);
    });
  });
}

async function login() {
  if (!USERNAME || !PASSWORD) return "";
  const response = await requestJson("POST", "/login", { username: USERNAME, password: PASSWORD });
  return response.token || "";
}

async function main() {
  if (hasSubtitle(target) && !FORCE) {
    console.log(`[subs] exists ${target}`);
    return;
  }
  const info = parseVideoInfo(target);
  if (!info.query) {
    console.log(`[subs] skipped unparsed query ${target}`);
    return;
  }
  if (info.type === "episode") {
    const params = new URLSearchParams();
    params.set("episode_number", String(info.episode));
    params.set("languages", LANGUAGE);
    params.set("query", canonicalQueryValue(info.query));
    params.set("season_number", String(info.season));
    params.set("type", "episode");
    const token = await login().catch(() => "");
    const results = await requestJson("GET", `/subtitles?${params.toString()}`, null, token);
    await saveFirstSubtitle(results, token);
  } else {
    const params = new URLSearchParams();
    params.set("languages", LANGUAGE);
    params.set("query", canonicalQueryValue(info.query));
    params.set("type", "movie");
    if (info.year) params.set("year", String(info.year));
    const token = await login().catch(() => "");
    const results = await requestJson("GET", `/subtitles?${params.toString()}`, null, token);
    await saveFirstSubtitle(results, token);
  }
}

async function saveFirstSubtitle(results, token) {
  const entries = Array.isArray(results.data) ? results.data : [];
  const ranked = entries
    .filter((entry) => entry.attributes?.files?.[0]?.file_id)
    .map((entry) => ({ entry, score: subtitleScore(entry) }))
    .filter((item) => item.score > -1000)
    .sort((a, b) => b.score - a.score);
  const first = ranked[0]?.entry;
  if (!first) {
    console.log(`[subs] none ${target}`);
    return;
  }
  console.log(`[subs] selected ${subtitleLabel(first)} score=${ranked[0].score}`);
  const fileId = first.attributes.files[0].file_id;
  const download = await requestJson("POST", "/download", { file_id: fileId, sub_format: "srt" }, token);
  if (!download.link) throw new Error("download link missing");
  const out = subtitleTargets(target)[0];
  await downloadFile(download.link, out);
  console.log(`[subs] saved ${out}`);
}

function subtitleLabel(entry) {
  const attrs = entry.attributes || {};
  const file = attrs.files?.[0] || {};
  return cleanNamePart([
    attrs.release,
    attrs.feature_details?.title,
    attrs.feature_details?.episode_title,
    file.file_name,
  ].filter(Boolean).join(" | "));
}

function subtitleScore(entry) {
  const attrs = entry.attributes || {};
  const file = attrs.files?.[0] || {};
  const label = subtitleLabel(entry).toLowerCase();
  let score = 0;

  if (attrs.from_trusted) score += 80;
  if (attrs.ai_translated === false) score += 20;
  if (attrs.machine_translated === false) score += 20;
  if (attrs.hearing_impaired === false) score += 20;
  if (attrs.hd) score += 5;
  if (attrs.votes) score += Math.min(25, Number(attrs.votes) || 0);
  if (attrs.ratings) score += Math.min(20, Number(attrs.ratings) || 0);
  if (attrs.download_count) score += Math.min(30, Math.floor((Number(attrs.download_count) || 0) / 1000));

  if (attrs.ai_translated === true) score -= 50;
  if (attrs.machine_translated === true) score -= 50;
  if (attrs.hearing_impaired === true) score -= 35;

  for (const bad of ["commentary", "comment", "dvd extras", "behind the scenes", "interview"]) {
    if (label.includes(bad)) score -= 500;
  }
  for (const good of ["web", "webrip", "web-dl", "hdtv", "bluray", "bdrip", "dvdrip", "proper"]) {
    if (label.includes(good)) score += 8;
  }

  const bytes = Number(file.file_size || attrs.file_size || 0);
  if (bytes > 0 && bytes < 15000) score -= 20;
  if (bytes > 25000 && bytes < 90000) score += 10;

  return score;
}

main().catch((err) => {
  console.log(`[subs] error ${target}: ${err.message}`);
  process.exit(0);
});
