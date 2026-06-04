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
const TVSUBTITLES_BASE_URL = "https://www.tvsubtitles.net";
const OPEN_SUBTITLES_FALLBACK = process.env.ROKU_SUBTITLE_OPEN_SUBTITLES_FALLBACK === "1"
  || process.env.OPEN_SUBTITLES_FALLBACK === "1"
  || process.argv.includes("--open-fallback");
const TVSUBTITLES_FALLBACK = process.env.ROKU_SUBTITLE_TVSUBTITLES !== "0"
  && !process.argv.includes("--no-tvsubtitles");
const COMMENTARY_SALVAGE = process.env.ROKU_SUBTITLE_COMMENTARY_SALVAGE !== "0";
const SUBTITLE_AUTOSYNC = process.env.ROKU_SUBTITLE_AUTOSYNC !== "0";
const FFSUBSYNC_CANDIDATES = [
  process.env.FFSUBSYNC_BIN,
  path.join(__dirname, ".venv/bin/ffsubsync"),
  "/volume1/docker/roku-ds-video-tools/.venv/bin/ffsubsync",
  "ffsubsync",
].filter(Boolean);
const FFMPEG_PATH_DIRS = [
  "/usr/local/bin",
  "/usr/bin",
  "/volume1/@appstore/ffmpeg7/bin",
  "/volume1/@appstore/ffmpeg/bin",
  "/volume1/@appstore/VideoStation/bin",
  "/volume1/@appstore/MediaServer/bin",
  "/volume1/@appstore/EmbyServer/bin",
];

const target = process.argv.slice(2).find((arg) => !arg.startsWith("--"));
const FORCE = process.argv.includes("--force");

if (!target) {
  console.error("usage: SUBDL_API_KEY=... or OPEN_SUBTITLES_API_KEY=... node download-subtitles.js /path/video.mp4");
  process.exit(2);
}
if (!SUBDL_API_KEY && !OPEN_SUBTITLES_API_KEY && !TVSUBTITLES_FALLBACK) {
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
    const title = cleanNamePart(base
      .slice(episodeMatch.index + episodeMatch[0].length)
      .replace(/^[-\s]+/, "")
      .replace(/\b(2160p|1080p|720p|480p|web[-_. ]?dl|webrip|hdtv|bdrip|bluray|x264|x265|h264|h265|aac|dts)\b.*$/i, ""));
    return {
      type: "episode",
      query: show,
      season: Number(episodeMatch[1]),
      episode: Number(episodeMatch[2]),
      title,
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

function meaningfulTitleTokens(value) {
  const stop = new Set(["and", "the", "for", "with", "from", "that", "this", "into", "onto", "part", "episode"]);
  return canonicalQueryValue(value)
    .split(/\s+/)
    .filter((token) => token.length >= 3 || /^\d+$/.test(token))
    .filter((token) => !stop.has(token));
}

function titleTokenMatches(label, title) {
  const tokens = meaningfulTitleTokens(title);
  if (tokens.length === 0) return 0;
  return tokens.filter((token) => label.includes(token)).length;
}

function titleTokenScore(label, title) {
  const tokens = meaningfulTitleTokens(title);
  if (tokens.length === 0) return 0;
  const lower = canonicalQueryValue(label);
  return tokens.filter((token) => lower.includes(token)).length * 100 - Math.abs(tokens.length - titleTokenMatches(lower, title));
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

function existingSubtitle(filePath) {
  return subtitleTargets(filePath).find((candidate) => fs.existsSync(candidate)) || "";
}

const COMMENTARY_PHRASES = [
  "audio commentary",
  "commentary track",
  "director commentary",
  "director's commentary",
  "fireside chat",
  "with the creators of south park",
  "matt stone and trey parker",
  "matt stone",
  "trey parker",
];

function hasCommentaryText(text) {
  const lower = String(text || "").toLowerCase();
  return COMMENTARY_PHRASES.some((phrase) => lower.includes(phrase));
}

function subtitleTextLooksBad(filePath) {
  try {
    return hasCommentaryText(fs.readFileSync(filePath, "utf8").slice(0, 8000));
  } catch {
    return false;
  }
}

function sanitizeCommentarySubtitle(filePath) {
  if (!COMMENTARY_SALVAGE) return false;
  let input = "";
  try {
    input = fs.readFileSync(filePath, "utf8");
  } catch {
    return false;
  }
  const blocks = input
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter(Boolean);
  const kept = blocks.filter((block) => !hasCommentaryText(block));
  if (kept.length < 5 || kept.length === blocks.length) return false;
  const output = kept.map((block, index) => {
    const lines = block.split("\n");
    if (/^\d+$/.test(lines[0] || "")) lines.shift();
    return [String(index + 1), ...lines].join("\n");
  }).join("\n\n") + "\n";
  if (hasCommentaryText(output.slice(0, 8000))) return false;
  fs.writeFileSync(filePath, output);
  console.log(`[subs] trimmed commentary blocks ${blocks.length - kept.length}/${blocks.length}`);
  return true;
}

function commandAvailable(command, args = ["--version"]) {
  const result = spawnSync(command, args, { encoding: "utf8", timeout: 10000 });
  return !result.error && result.status === 0;
}

function ffsubsyncCommand() {
  return FFSUBSYNC_CANDIDATES.find((candidate) => commandAvailable(candidate)) || "";
}

function syncSubtitleWithAudio(filePath) {
  const ffsubsync = SUBTITLE_AUTOSYNC ? ffsubsyncCommand() : "";
  if (!ffsubsync) return false;
  const tmp = `${filePath}.sync.srt`;
  fs.rmSync(tmp, { force: true });
  const result = spawnSync(ffsubsync, [target, "-i", filePath, "-o", tmp], {
    encoding: "utf8",
    env: { ...process.env, PATH: `${FFMPEG_PATH_DIRS.join(":")}:${process.env.PATH || ""}` },
    timeout: 10 * 60 * 1000,
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0 || !fs.existsSync(tmp)) {
    fs.rmSync(tmp, { force: true });
    console.log(`[subs] autosync skipped ${result.stderr || result.stdout || "ffsubsync failed"}`.trim());
    return false;
  }
  fs.renameSync(tmp, filePath);
  console.log("[subs] autosynced with audio");
  return true;
}

function acceptSavedSubtitle(filePath, label) {
  if (!subtitleTextLooksBad(filePath)) {
    syncSubtitleWithAudio(filePath);
    return true;
  }
  if (sanitizeCommentarySubtitle(filePath)) {
    syncSubtitleWithAudio(filePath);
    return true;
  }
  fs.rmSync(filePath, { force: true });
  console.log(`[subs] rejected commentary ${label || filePath}`);
  return false;
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

function requestTvSubtitles(endpoint, options = {}, redirectCount = 0) {
  return new Promise((resolve, reject) => {
    const jar = options.jar || {};
    const targetUrl = /^https?:\/\//i.test(endpoint) ? endpoint : `${TVSUBTITLES_BASE_URL}${endpoint}`;
    const body = options.body || "";
    const headers = {
      "Accept": options.binary ? "*/*" : "text/html,application/xhtml+xml",
      "User-Agent": USER_AGENT,
      ...(Object.keys(jar).length ? { Cookie: Object.entries(jar).map(([key, value]) => `${key}=${value}`).join("; ") } : {}),
      ...(body ? {
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": Buffer.byteLength(body),
      } : {}),
    };
    const req = https.request(targetUrl, { method: body ? "POST" : "GET", headers }, (res) => {
      for (const cookie of res.headers["set-cookie"] || []) {
        const first = cookie.split(";")[0] || "";
        const idx = first.indexOf("=");
        if (idx > 0) jar[first.slice(0, idx)] = first.slice(idx + 1);
      }
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const buffer = Buffer.concat(chunks);
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirectCount < 5) {
          const next = new URL(res.headers.location, targetUrl).href;
          return requestTvSubtitles(next, { ...options, body: "" }, redirectCount + 1).then(resolve).catch(reject);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) return reject(new Error(`tvsubtitles ${res.statusCode}`));
        resolve(options.binary ? buffer : buffer.toString("utf8"));
      });
    });
    req.on("error", reject);
    if (body) req.write(body);
    req.end();
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
  extractZipSubtitle(tmpZip, filePath, preferredEntry);
}

function zipSubtitleEntries(tmpZip) {
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
    throw new Error("zip extractor not available or invalid subtitle zip");
  }
  return {
    archiveTool,
    entries: entries.filter((line) => /\.(srt|vtt)$/i.test(line) && !/^__MACOSX\//i.test(line)),
  };
}

function extractZipSubtitle(tmpZip, filePath, preferredEntry = "") {
  const { archiveTool, entries } = zipSubtitleEntries(tmpZip);
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

function normalizeSubtitleFile(filePath) {
  let input = "";
  try {
    input = fs.readFileSync(filePath, "utf8");
  } catch {
    return false;
  }
  if (/\d{2}:\d{2}:\d{2}[,.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,.]\d{3}/.test(input)) return false;
  const lines = input.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  const entries = [];
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].trim().match(/^(\d{2}:\d{2}:\d{2}[,.]\d{1,3}),(\d{2}:\d{2}:\d{2}[,.]\d{1,3})$/);
    if (!match) continue;
    const start = normalizeSubtitleTime(match[1]);
    const end = normalizeSubtitleTime(match[2]);
    const text = [];
    for (i++; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) break;
      if (/^\[.*\]$/.test(line)) continue;
      text.push(line.replace(/\[br\]/gi, "\n"));
    }
    if (start && end && text.length) entries.push({ start, end, text: text.join("\n") });
  }
  if (entries.length === 0) return false;
  const output = entries.map((entry, index) => `${index + 1}\n${entry.start} --> ${entry.end}\n${entry.text}\n`).join("\n");
  fs.writeFileSync(filePath, output);
  console.log(`[subs] normalized subtitle format ${entries.length} cues`);
  return true;
}

function normalizeSubtitleTime(value) {
  const match = String(value || "").trim().match(/^(\d{2}):(\d{2}):(\d{2})[,.](\d{1,3})$/);
  if (!match) return "";
  return `${match[1]}:${match[2]}:${match[3]},${match[4].padEnd(3, "0").slice(0, 3)}`;
}

async function login() {
  if (!OPEN_SUBTITLES_USERNAME || !OPEN_SUBTITLES_PASSWORD) return "";
  const response = await requestOpenSubtitlesJson("POST", "/login", { username: OPEN_SUBTITLES_USERNAME, password: OPEN_SUBTITLES_PASSWORD });
  return response.token || "";
}

async function main() {
  const existing = existingSubtitle(target);
  if (existing && !FORCE) {
    normalizeSubtitleFile(existing);
    acceptSavedSubtitle(existing, existing);
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
  }
  if (TVSUBTITLES_FALLBACK && info.type === "episode" && LANGUAGE.toLowerCase() === "en") {
    const saved = await saveFromTvSubtitles(info).catch((err) => {
      console.log(`[subs] tvsubtitles error ${target}: ${err.message}`);
      return false;
    });
    if (saved) return;
  }
  if (SUBDL_API_KEY) {
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

async function saveFromTvSubtitles(info) {
  const jar = {};
  const search = await requestTvSubtitles("/search1.php", {
    jar,
    body: new URLSearchParams({ qs: info.query }).toString(),
  });
  const show = bestTvSubtitlesShow(search, info.query);
  if (!show) {
    console.log(`[subs] tvsubtitles none ${target}`);
    return false;
  }
  await requestTvSubtitles("/setuser.php", { jar }).catch(() => "");
  const seasonPath = `/subtitle-${show.id}-${info.season}-en.html`;
  const seasonPage = await requestTvSubtitles(seasonPath, { jar });
  if (!seasonPage.includes(`download-${show.id}-${info.season}-en.html`)) {
    console.log(`[subs] tvsubtitles no season ${target}`);
    return false;
  }
  const downloadHtml = await requestTvSubtitles(`/download-${show.id}-${info.season}-en.html`, { jar, binary: true });
  const zip = zipBufferFromTvSubtitlesDownload(downloadHtml, jar);
  const out = subtitleTargets(target)[0];
  const tmpZip = `${out}.tvsubtitles.ziptmp`;
  fs.rmSync(out, { force: true });
  fs.writeFileSync(tmpZip, await zip);
  try {
    const entry = bestZipEntryForEpisode(tmpZip, info);
    extractZipSubtitle(tmpZip, out, entry);
  } finally {
    fs.rmSync(tmpZip, { force: true });
  }
  normalizeSubtitleFile(out);
  if (!acceptSavedSubtitle(out, `tvsubtitles ${show.title} s${info.season} ${info.title}`)) return false;
  console.log(`[subs] tvsubtitles saved ${out}`);
  return true;
}

function bestTvSubtitlesShow(html, query) {
  const shows = [];
  const re = /<a\s+href="\/tvshow-(\d+)\.html">([^<]+)<\/a>/gi;
  let match;
  while ((match = re.exec(html))) {
    const title = cleanNamePart(match[2].replace(/\([^)]*\)/g, ""));
    shows.push({ id: match[1], title, score: titleTokenScore(title, query) });
  }
  return shows.sort((a, b) => b.score - a.score)[0] || null;
}

async function zipBufferFromTvSubtitlesDownload(bufferOrHtml, jar) {
  const buffer = Buffer.isBuffer(bufferOrHtml) ? bufferOrHtml : Buffer.from(String(bufferOrHtml || ""));
  if (buffer.slice(0, 2).toString("binary") === "PK") return buffer;
  const html = buffer.toString("utf8");
  const vars = {};
  for (const match of html.matchAll(/var\s+(s\d+)\s*=\s*'([^']*)'/g)) vars[match[1]] = match[2];
  const order = [...html.matchAll(/document\.location\s*=\s*([^;]+)/g)][0]?.[1] || "";
  const relative = (order.match(/s\d+/g) || []).map((key) => vars[key] || "").join("");
  if (!relative) throw new Error("TVsubtitles download redirect missing");
  const zip = await requestTvSubtitles(new URL(relative, TVSUBTITLES_BASE_URL).href, { jar, binary: true });
  if (zip.slice(0, 2).toString("binary") !== "PK") throw new Error("TVsubtitles download was not a zip");
  return zip;
}

function bestZipEntryForEpisode(tmpZip, info) {
  const { entries } = zipSubtitleEntries(tmpZip);
  if (entries.length === 0) throw new Error("TVsubtitles zip did not contain srt/vtt");
  const marker = new RegExp(`\\b${info.season}\\s*x\\s*${String(info.episode).padStart(2, "0")}\\b|\\b${info.season}\\s*x\\s*${info.episode}\\b`, "i");
  const ranked = entries.map((entry) => {
    const base = cleanNamePart(path.basename(entry));
    let score = titleTokenScore(base, info.title);
    if (marker.test(base)) score += 1000;
    if (/\ben\b/i.test(base)) score += 5;
    return { entry, score };
  }).sort((a, b) => b.score - a.score);
  return ranked[0].entry;
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
  if (ranked.length === 0) {
    if (!quietNone) console.log(`[subs] subdl none ${target}`);
    return false;
  }
  const out = subtitleTargets(target)[0];
  for (const first of ranked) {
    fs.rmSync(out, { force: true });
    const label = subdlSubtitleLabel(first.entry, first.unpacked);
    console.log(`[subs] subdl selected ${label} score=${first.score}`);
    try {
      const relativeUrl = first.unpacked?.url || first.entry.url;
      if (!relativeUrl) {
        console.log(`[subs] subdl missing download url ${target}`);
        continue;
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
    } catch (err) {
      fs.rmSync(out, { force: true });
      console.log(`[subs] subdl candidate failed ${label}: ${err.message}`);
      continue;
    }
    if (!acceptSavedSubtitle(out, label)) continue;
    console.log(`[subs] saved ${out}`);
    return true;
  }
  if (!quietNone) console.log(`[subs] subdl none ${target}`);
  return false;
}

async function saveFirstOpenSubtitles(results, token) {
  const entries = Array.isArray(results.data) ? results.data : [];
  const ranked = entries
    .filter((entry) => entry.attributes?.files?.[0]?.file_id)
    .map((entry) => ({ entry, score: subtitleScore(entry) }))
    .filter((item) => item.score > -1000)
    .sort((a, b) => b.score - a.score);
  if (ranked.length === 0) {
    console.log(`[subs] none ${target}`);
    return;
  }
  const out = subtitleTargets(target)[0];
  for (const item of ranked) {
    fs.rmSync(out, { force: true });
    const first = item.entry;
    const label = subtitleLabel(first);
    console.log(`[subs] selected ${label} score=${item.score}`);
    const fileId = first.attributes.files[0].file_id;
    const download = await requestOpenSubtitlesJson("POST", "/download", { file_id: fileId, sub_format: "srt" }, token);
    if (!download.link) throw new Error("download link missing");
    await downloadFile(download.link, out);
    if (!acceptSavedSubtitle(out, label)) continue;
    console.log(`[subs] saved ${out}`);
    return;
  }
  console.log(`[subs] none ${target}`);
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
  const itemLabel = cleanNamePart([
    unpacked?.release_name,
    unpacked?.name,
    unpacked ? "" : entry.release_name,
    unpacked ? "" : entry.name,
  ].filter(Boolean).join(" | ")).toLowerCase();
  let score = 0;
  const season = Number(unpacked?.season || entry.season || 0);
  const episode = Number(unpacked?.episode || entry.episode || 0);
  const format = String(unpacked?.format || entry.format || "").toLowerCase();
  const size = Number(unpacked?.size || entry.size || 0);
  const hi = unpacked?.hi ?? entry.hi;

  for (const bad of ["commentary", "comment", "dvd extras", "behind the scenes", "interview"]) {
    if (itemLabel.includes(bad)) {
      if (!COMMENTARY_SALVAGE || bad !== "commentary") return -10000;
      score -= 850;
      break;
    }
  }

  if (info.type === "episode") {
    if (unpacked && Number(unpacked.episode || 0) === 0 && /\b00\b/.test(itemLabel)) return -10000;
    if (/(^|[\/\s._-])00([\/\s._-]|$)/.test(itemLabel)) return -10000;
    const marker = episodeMarker(label);
    const titleMatches = titleTokenMatches(label, info.title);
    if (info.title && titleMatches === 0) return -10000;
    score += titleMatches * 25;
    if (marker && marker.season !== info.season) return -10000;
    if (marker && marker.episode !== info.episode) {
      if (titleMatches > 0) score -= 80;
      else return -10000;
    }
    if (season === info.season) score += 80;
    if (episode === info.episode) score += 100;
    if (season && season !== info.season) return -10000;
    if (episode && episode !== info.episode) {
      if (titleMatches > 0) score -= 80;
      else return -10000;
    }
  }
  if (format === "srt") score += 30;
  if (format === "vtt") score += 10;
  if (hi === false) score += 20;
  if (hi === true) score -= 25;
  if (entry.full_season && !unpacked) score -= 100;

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

  for (const bad of ["commentary", "comment", "dvd extras", "behind the scenes", "interview"]) {
    if (label.includes(bad)) {
      if (!COMMENTARY_SALVAGE || bad !== "commentary") return -10000;
      score -= 850;
      break;
    }
  }

  if (info.type === "episode") {
    const marker = episodeMarker(label);
    if (marker && (marker.season !== info.season || marker.episode !== info.episode)) return -10000;
    const titleMatches = titleTokenMatches(label, info.title);
    if (info.title && titleMatches === 0) return -10000;
    score += titleMatches * 25;
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
