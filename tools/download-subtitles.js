#!/usr/bin/env node
const fs = require("fs");
const https = require("https");
const path = require("path");
const { spawnSync } = require("child_process");

const OPEN_SUBTITLES_API_KEY = process.env.OPEN_SUBTITLES_API_KEY || process.env.OPENSUBTITLES_API_KEY || "";
const OPEN_SUBTITLES_USERNAME = process.env.OPEN_SUBTITLES_USERNAME || process.env.OPENSUBTITLES_USERNAME || "";
const OPEN_SUBTITLES_PASSWORD = process.env.OPEN_SUBTITLES_PASSWORD || process.env.OPENSUBTITLES_PASSWORD || "";
const SUBDL_API_KEY = process.env.SUBDL_API_KEY || "";
const LANGUAGE = process.env.OPEN_SUBTITLES_LANGUAGE || process.env.SUBDL_LANGUAGE || "en";
const USER_AGENT = process.env.OPEN_SUBTITLES_USER_AGENT || "RokuDSVideo v1.0";
const OPEN_SUBTITLES_BASE_URL = "https://api.opensubtitles.com/api/v1";
const SUBDL_BASE_URL = "https://api.subdl.com/api/v1";
const SUBDL_DOWNLOAD_BASE_URL = "https://dl.subdl.com";
const OPEN_SUBTITLES_FALLBACK = process.env.ROKU_SUBTITLE_OPEN_SUBTITLES_FALLBACK === "1"
  || process.env.OPEN_SUBTITLES_FALLBACK === "1"
  || process.argv.includes("--open-fallback");

const target = process.argv.slice(2).find((arg) => !arg.startsWith("--"));
const FORCE = process.argv.includes("--force");

if (!target) {
  console.error("usage: SUBDL_API_KEY=... or OPEN_SUBTITLES_API_KEY=... node download-subtitles.js /path/video.mp4");
  process.exit(2);
}
if (!SUBDL_API_KEY && !OPEN_SUBTITLES_API_KEY) {
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
  if (norm === "movies" || norm === "movie") return "Movies";
  return "";
}

function parseVideoInfo(filePath) {
  const parts = String(filePath || "").replace(/\\/g, "/").split("/").filter(Boolean);
  const fileName = parts[parts.length - 1] || "";
  const base = withoutVideoExtension(fileName).replace(/[._]+/g, " ");
  const episodeMatch = base.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || base.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  const libraryIndex = parts.findIndex((part) => libraryNameForPart(part));
  const library = libraryIndex >= 0 ? libraryNameForPart(parts[libraryIndex]) : "";
  if (episodeMatch && library === "TV Shows") {
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

function episodeMarker(value) {
  const text = String(value || "");
  const match = text.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || text.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  if (!match) return null;
  return { season: Number(match[1]), episode: Number(match[2]) };
}

function subdlLanguage(value) {
  const code = String(value || "en").trim();
  if (!code) return "EN";
  if (code.toLowerCase() === "en") return "EN";
  return code.toUpperCase();
}

function hasSubtitle(filePath) {
  return subtitleTargets(filePath).some((candidate) => fs.existsSync(candidate));
}

function requestOpenSubtitlesJson(method, endpoint, body, token = "", redirectCount = 0) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : "";
    const targetUrl = /^https?:\/\//i.test(endpoint) ? endpoint : `${OPEN_SUBTITLES_BASE_URL}${endpoint}`;
    const req = https.request(targetUrl, {
      method,
      headers: {
        "Api-Key": OPEN_SUBTITLES_API_KEY,
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
          return requestOpenSubtitlesJson(method, next.href, body, token, redirectCount + 1)
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

function requestSubdlJson(endpoint, redirectCount = 0) {
  return new Promise((resolve, reject) => {
    const targetUrl = /^https?:\/\//i.test(endpoint) ? endpoint : `${SUBDL_BASE_URL}${endpoint}`;
    https.get(targetUrl, {
      headers: {
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
      },
    }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirectCount < 5) {
          const next = new URL(res.headers.location, targetUrl);
          return requestSubdlJson(next.href, redirectCount + 1).then(resolve).catch(reject);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) return reject(new Error(`${res.statusCode} ${text.slice(0, 200)}`));
        try {
          resolve(JSON.parse(text || "{}"));
        } catch (err) {
          reject(err);
        }
      });
    }).on("error", reject);
  });
}

function downloadFile(url, filePath, redirectCount = 0, headers = {}) {
  return new Promise((resolve, reject) => {
    const tmp = `${filePath}.tmp`;
    fs.rmSync(tmp, { force: true });
    const out = fs.createWriteStream(tmp);
    https.get(url, { headers: { "User-Agent": USER_AGENT, ...headers } }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirectCount < 5) {
        out.close(() => fs.rmSync(tmp, { force: true }));
        const next = new URL(res.headers.location, url).href;
        return downloadFile(next, filePath, redirectCount + 1, headers).then(resolve).catch(reject);
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

async function downloadZipSubtitle(url, filePath, preferredEntry = "") {
  const tmpZip = `${filePath}.ziptmp`;
  fs.rmSync(tmpZip, { force: true });
  await downloadFile(url, tmpZip);
  let archiveTool = "unzip";
  let list = spawnSync("unzip", ["-Z1", tmpZip], { encoding: "utf8", timeout: 30000 });
  let entries = [];
  if (list.status === 0) {
    entries = String(list.stdout || "")
      .split("\n")
      .map((line) => line.trim());
  } else {
    archiveTool = "7z";
    list = spawnSync("7z", ["l", "-slt", tmpZip], { encoding: "utf8", timeout: 30000 });
    if (list.status === 0) {
      entries = String(list.stdout || "")
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.startsWith("Path = "))
        .map((line) => line.slice("Path = ".length).trim());
    }
  }
  if (list.status !== 0) {
    fs.rmSync(tmpZip, { force: true });
    throw new Error("zip extractor not available or invalid subtitle zip");
  }
  entries = entries
    .filter((line) => /\.(srt|vtt)$/i.test(line) && !/^__MACOSX\//i.test(line));
  const preferredBase = cleanNamePart(path.basename(preferredEntry || "")).toLowerCase();
  const entry = (preferredBase
    ? entries.find((line) => cleanNamePart(path.basename(line)).toLowerCase() === preferredBase)
    : "") || entries[0];
  if (!entry) {
    fs.rmSync(tmpZip, { force: true });
    throw new Error("subtitle zip did not contain srt/vtt");
  }
  const extractedArgs = archiveTool === "unzip" ? ["-p", tmpZip, entry] : ["x", "-so", tmpZip, entry];
  const extracted = spawnSync(archiveTool, extractedArgs, {
    encoding: "buffer",
    timeout: 30000,
    maxBuffer: 20 * 1024 * 1024,
  });
  fs.rmSync(tmpZip, { force: true });
  if (extracted.status !== 0 || !extracted.stdout?.length) throw new Error("failed to extract subtitle from zip");
  const tmpOut = `${filePath}.tmp`;
  fs.writeFileSync(tmpOut, extracted.stdout);
  fs.renameSync(tmpOut, filePath);
}

async function login() {
  if (!OPEN_SUBTITLES_USERNAME || !OPEN_SUBTITLES_PASSWORD) return "";
  const response = await requestOpenSubtitlesJson("POST", "/login", { username: OPEN_SUBTITLES_USERNAME, password: OPEN_SUBTITLES_PASSWORD });
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
  if (SUBDL_API_KEY) {
    const saved = await saveFromSubdl(info).catch((err) => {
      console.log(`[subs] subdl error ${target}: ${err.message}`);
      return false;
    });
    if (saved) return;
    if (OPEN_SUBTITLES_API_KEY && !OPEN_SUBTITLES_FALLBACK) {
      console.log(`[subs] none ${target} (OpenSubtitles fallback disabled)`);
      return;
    }
  }
  if (!OPEN_SUBTITLES_API_KEY) {
    console.log(`[subs] none ${target}`);
    return;
  }
  await saveFromOpenSubtitles(info);
}

async function saveFromOpenSubtitles(info) {
  if (info.type === "episode") {
    const params = new URLSearchParams();
    params.set("episode_number", String(info.episode));
    params.set("languages", LANGUAGE);
    params.set("query", canonicalQueryValue(info.query));
    params.set("season_number", String(info.season));
    params.set("type", "episode");
    const token = await login().catch(() => "");
    const results = await requestOpenSubtitlesJson("GET", `/subtitles?${params.toString()}`, null, token);
    await saveFirstOpenSubtitles(results, token);
  } else {
    const params = new URLSearchParams();
    params.set("languages", LANGUAGE);
    params.set("query", canonicalQueryValue(info.query));
    params.set("type", "movie");
    if (info.year) params.set("year", String(info.year));
    const token = await login().catch(() => "");
    const results = await requestOpenSubtitlesJson("GET", `/subtitles?${params.toString()}`, null, token);
    await saveFirstOpenSubtitles(results, token);
  }
}

async function saveFromSubdl(info) {
  const params = new URLSearchParams();
  params.set("api_key", SUBDL_API_KEY);
  params.set("film_name", canonicalQueryValue(info.query));
  params.set("languages", subdlLanguage(LANGUAGE));
  params.set("subs_per_page", "30");
  params.set("releases", "1");
  params.set("hi", "1");
  params.set("unpack", "1");
  if (info.type === "episode") {
    params.set("type", "tv");
    params.set("season_number", String(info.season));
    params.set("episode_number", String(info.episode));
  } else {
    params.set("type", "movie");
    if (info.year) params.set("year", String(info.year));
  }
  const titleResults = await requestSubdlJson(`/subtitles?${params.toString()}`);
  if (titleResults.status === false) throw new Error(titleResults.error || "SubDL search failed");
  if (await saveFirstSubdl(titleResults, info, false)) return true;

  const fileParams = new URLSearchParams();
  fileParams.set("api_key", SUBDL_API_KEY);
  fileParams.set("file_name", path.basename(target));
  fileParams.set("languages", subdlLanguage(LANGUAGE));
  fileParams.set("subs_per_page", "30");
  fileParams.set("releases", "1");
  fileParams.set("hi", "1");
  fileParams.set("unpack", "1");
  const fileResults = await requestSubdlJson(`/subtitles?${fileParams.toString()}`);
  if (fileResults.status === false) throw new Error(fileResults.error || "SubDL file search failed");
  return saveFirstSubdl(fileResults, info, true);
}

async function saveFirstSubdl(results, info, quietNone = false) {
  const entries = Array.isArray(results.subtitles) ? results.subtitles : [];
  const flattened = [];
  for (const entry of entries) {
    if (Array.isArray(entry.unpack_files) && entry.unpack_files.length > 0) {
      for (const unpacked of entry.unpack_files) flattened.push({ entry, unpacked, score: subdlSubtitleScore(entry, unpacked, info) });
    } else {
      flattened.push({ entry, unpacked: null, score: subdlSubtitleScore(entry, null, info) });
    }
  }
  const ranked = flattened
    .filter((item) => item.score > -1000)
    .sort((a, b) => b.score - a.score);
  const first = ranked[0];
  if (!first) {
    if (!quietNone) console.log(`[subs] subdl none ${target}`);
    return false;
  }
  const out = subtitleTargets(target)[0];
  const label = subdlSubtitleLabel(first.entry, first.unpacked);
  console.log(`[subs] subdl selected ${label} score=${first.score}`);
  const relativeUrl = first.unpacked?.url || first.entry.url;
  if (!relativeUrl) {
    console.log(`[subs] subdl missing download url ${target}`);
    return false;
  }
  const downloadUrl = /^https?:\/\//i.test(relativeUrl) ? relativeUrl : `${SUBDL_DOWNLOAD_BASE_URL}${relativeUrl}`;
  if (first.unpacked?.url) {
    try {
      await downloadFile(downloadUrl, out);
    } catch (err) {
      if (!first.entry.url) throw err;
      const zipUrl = /^https?:\/\//i.test(first.entry.url) ? first.entry.url : `${SUBDL_DOWNLOAD_BASE_URL}${first.entry.url}`;
      await downloadZipSubtitle(zipUrl, out, first.unpacked.name || first.unpacked.release_name || "");
    }
  } else {
    await downloadZipSubtitle(downloadUrl, out);
  }
  console.log(`[subs] saved ${out}`);
  return true;
}

async function saveFirstOpenSubtitles(results, token) {
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
  const download = await requestOpenSubtitlesJson("POST", "/download", { file_id: fileId, sub_format: "srt" }, token);
  if (!download.link) throw new Error("download link missing");
  const out = subtitleTargets(target)[0];
  await downloadFile(download.link, out);
  console.log(`[subs] saved ${out}`);
}

function subdlSubtitleLabel(entry, unpacked) {
  return cleanNamePart([
    unpacked?.release_name,
    unpacked?.name,
    entry.release_name,
    entry.name,
  ].filter(Boolean).join(" | "));
}

function subdlSubtitleScore(entry, unpacked, info) {
  const label = subdlSubtitleLabel(entry, unpacked).toLowerCase();
  let score = 0;
  const season = Number(unpacked?.season || entry.season || 0);
  const episode = Number(unpacked?.episode || entry.episode || 0);
  const format = String(unpacked?.format || entry.format || "").toLowerCase();
  const size = Number(unpacked?.size || entry.size || 0);
  const hi = unpacked?.hi ?? entry.hi;

  if (info.type === "episode") {
    const marker = episodeMarker(label);
    if (marker && (marker.season !== info.season || marker.episode !== info.episode)) return -10000;
    if (season === info.season) score += 80;
    if (episode === info.episode) score += 100;
    if (season && season !== info.season) return -10000;
    if (episode && episode !== info.episode) return -10000;
  }
  if (format === "srt") score += 30;
  if (format === "vtt") score += 10;
  if (hi === false) score += 20;
  if (hi === true) score -= 25;
  if (entry.full_season && !unpacked) score -= 100;

  for (const bad of ["commentary", "comment", "dvd extras", "behind the scenes", "interview"]) {
    if (label.includes(bad)) score -= 500;
  }
  for (const good of ["web", "webrip", "web-dl", "hdtv", "bluray", "bdrip", "dvdrip", "proper"]) {
    if (label.includes(good)) score += 8;
  }
  if (size > 0 && size < 15000) score -= 20;
  if (size > 25000 && size < 90000) score += 10;

  return score;
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
  const info = parseVideoInfo(target);

  if (info.type === "episode") {
    const marker = episodeMarker(label);
    if (marker && (marker.season !== info.season || marker.episode !== info.episode)) return -10000;
    const details = attrs.feature_details || {};
    const season = Number(details.season_number || details.season || 0);
    const episode = Number(details.episode_number || details.episode || 0);
    if (season && season !== info.season) return -10000;
    if (episode && episode !== info.episode) return -10000;
  }

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
