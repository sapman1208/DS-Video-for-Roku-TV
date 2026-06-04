#!/usr/bin/env node
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
const allMode = args.includes("--all");
const dryRun = args.includes("--dry-run");
const force = args.includes("--force");
const limitArg = args.find((arg) => arg.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.split("=")[1]) || 0 : 0;
const positional = args.filter((arg) => !arg.startsWith("--"));
const sourcePath = positional[0] || "";
const targetVideoPath = positional[1] || "";
const overridePath = process.env.ROKU_VSMETA_OVERRIDES || path.join(__dirname, "vsmeta-overrides.json");

if (!allMode && (!sourcePath || !targetVideoPath)) {
  console.error("usage: generate-vsmeta.js <source-video-path> <target-video-path>");
  console.error("   or: generate-vsmeta.js --all [--dry-run] [--force] [--limit=N]");
  process.exit(2);
}

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runSql(sql) {
  const command = `psql -U VideoStation -d video_metadata -X -q -t -A -F "\t" -c "${sql.replace(/"/g, '\\"')}"`;
  const result = spawnSync("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `psql failed ${result.status}`).trim());
  }
  return String(result.stdout || "").trim();
}

function varint(num) {
  let value = Math.max(0, Number(num) || 0);
  const bytes = [];
  do {
    let byte = value & 0x7f;
    value = Math.floor(value / 128);
    if (value !== 0) byte |= 0x80;
    bytes.push(byte);
  } while (value !== 0);
  return Buffer.from(bytes);
}

function stringBytes(value) {
  const bytes = Buffer.from(String(value || ""), "utf8");
  return Buffer.concat([varint(bytes.length), bytes]);
}

function dateBytes(value) {
  const text = String(value || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return Buffer.alloc(0);
  return Buffer.concat([Buffer.from([0x0a]), Buffer.from(text, "utf8")]);
}

function tag(tagByte, value, kind = "string") {
  const tagBuffer = Buffer.isBuffer(tagByte) ? tagByte : Buffer.from([tagByte]);
  if (value === undefined || value === null) return tagBuffer;
  if (kind === "string") return Buffer.concat([tagBuffer, stringBytes(value)]);
  if (kind === "int") return Buffer.concat([tagBuffer, varint(value)]);
  if (kind === "bool") return Buffer.concat([tagBuffer, Buffer.from([value ? 0x01 : 0x00])]);
  if (kind === "date") return Buffer.concat([tagBuffer, dateBytes(value)]);
  if (kind === "raw") return Buffer.concat([tagBuffer, value]);
  if (kind === "content") return Buffer.concat([tagBuffer, varint(value.length), value]);
  return tagBuffer;
}

function imageTags(data, dataTag, md5Tag, index = 0) {
  if (!data || data.length === 0) return [];
  const b64 = data.toString("base64").replace(/.{76}/g, "$&\n");
  const md5 = crypto.createHash("md5").update(data).digest("hex");
  if (index > 0) {
    return [
      tag(dataTag),
      tag(index, b64),
      tag(md5Tag),
      tag(index, md5),
    ];
  }
  return [tag(dataTag, b64), tag(md5Tag, md5)];
}

function clean(value) {
  return String(value || "").replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim();
}

function loadOverrides() {
  try {
    if (!fs.existsSync(overridePath)) return {};
    return JSON.parse(fs.readFileSync(overridePath, "utf8"));
  } catch {
    return {};
  }
}

const metadataOverrides = loadOverrides();

function withoutVideoExtension(value) {
  return String(value || "").replace(/\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|webm)$/i, "");
}

function normalizeForCompare(value) {
  return clean(withoutVideoExtension(value))
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function libraryNameForPart(part) {
  const norm = normalizeForCompare(part);
  if (norm === "tv shows") return "TV Shows";
  return "";
}

function metadataOverride(showTitle, season, episode) {
  const key = `${normalizeForCompare(showTitle)}|${Number(season) || 0}|${Number(episode) || 0}`;
  return metadataOverrides[key] || {};
}

function applyEpisodeOverride(info) {
  if (!info) return info;
  const override = metadataOverride(info.showTitle, info.season, info.episode);
  if (override.title) info.episodeTitle = clean(override.title);
  if (override.summary) info.summary = String(override.summary || "").trim();
  return info;
}

function sourceCandidates(videoPath) {
  const cleanPath = String(videoPath || "").replace(/\\/g, "/");
  if (!cleanPath) return [];
  if (cleanPath.startsWith("/volume")) return [cleanPath];
  const rooted = cleanPath.startsWith("/") ? cleanPath : `/${cleanPath}`;
  return [rooted, `/volume1${rooted}`, `/volume2${rooted}`];
}

function generatedVideoPoster(videoPath) {
  for (const candidate of sourceCandidates(videoPath)) {
    const dir = path.dirname(candidate);
    const base = path.basename(candidate);
    const thumbDir = path.join(dir, "@eaDir", base);
    for (const name of [
      "SYNOVIDEO_VIDEO_POSTER.jpg",
      "SYNOVIDEO_VIDEO_POSTER_JPEGTN.jpg",
      "SYNOVIDEO_VIDEO_SCREENSHOT.jpg",
      "SYNOVIDEO_VIDEO_SCREENSHOT_JPEGTN.jpg",
    ]) {
      const file = path.join(thumbDir, name);
      try {
        if (fs.existsSync(file)) return fs.readFileSync(file);
      } catch {
        // try next
      }
    }
  }
  return Buffer.alloc(0);
}

function imageFromTable(table, mapperId) {
  if (!mapperId) return Buffer.alloc(0);
  const output = runSql(`select encode(lo_get(lo_oid), 'base64') from ${table} where mapper_id = ${Number(mapperId)} limit 1`);
  return output ? Buffer.from(output.replace(/\s+/g, ""), "base64") : Buffer.alloc(0);
}

function episodeInfo(videoPath) {
  const escaped = sqlEscape(videoPath);
  const rows = runSql(`
    select e.mapper_id, e.season, e.episode, e.tag_line, coalesce(s.summary, ''), t.title, t.mapper_id, coalesce(ts.summary, ''), coalesce(t.originally_available::text, ''), coalesce(e.originally_available::text, '')
    from video_file vf
    left join tvshow_episode e on e.id = vf.mapper_id or e.mapper_id = vf.mapper_id
    left join tvshow t on t.id = e.tvshow_id
    left join summary s on s.mapper_id = e.mapper_id
    left join summary ts on ts.mapper_id = t.mapper_id
    where vf.path = '${escaped}' or vf.path like '%${sqlEscape(path.basename(videoPath))}'
    order by case when vf.path = '${escaped}' then 0 else 1 end
    limit 1`);
  if (!rows) return null;
  const parts = rows.split("\t");
  if (parts.length < 7 || !parts[0]) return null;
  return applyEpisodeOverride({
    mapperId: parts[0],
    season: Number(parts[1]) || 0,
    episode: Number(parts[2]) || 0,
    episodeTitle: clean(parts[3]) || `Episode ${parts[2]}`,
    summary: parts[4] || "",
    showTitle: clean(parts[5]),
    showMapperId: parts[6],
    showSummary: parts[7] || "",
    showDate: /^\d{4}-\d{2}-\d{2}/.test(parts[8] || "") ? parts[8].slice(0, 10) : "",
    episodeDate: /^\d{4}-\d{2}-\d{2}/.test(parts[9] || "") ? parts[9].slice(0, 10) : "",
  });
}

function showInfoByTitle(showTitle) {
  if (!showTitle) return null;
  const escaped = sqlEscape(showTitle);
  const rows = runSql(`
    select t.mapper_id, t.title, coalesce(ts.summary, ''), coalesce(t.originally_available::text, '')
    from tvshow t
    left join summary ts on ts.mapper_id = t.mapper_id
    where lower(t.title) = lower('${escaped}')
       or lower(replace(replace(t.title, ':', ''), '!', '')) = lower(replace(replace('${escaped}', ':', ''), '!', ''))
    order by case when lower(t.title) = lower('${escaped}') then 0 else 1 end
    limit 1`);
  if (!rows) return null;
  const parts = rows.split("\t");
  if (parts.length < 2 || !parts[0]) return null;
  return {
    showMapperId: parts[0],
    showTitle: clean(parts[1]) || showTitle,
    showSummary: parts[2] || "",
    showDate: /^\d{4}-\d{2}-\d{2}/.test(parts[3] || "") ? parts[3].slice(0, 10) : "",
  };
}

function episodeInfoByShowSeasonEpisode(showTitle, season, episode) {
  if (!showTitle || !season || !episode) return null;
  const escaped = sqlEscape(showTitle);
  const rows = runSql(`
    select e.mapper_id, e.season, e.episode, e.tag_line, coalesce(s.summary, ''), t.title, t.mapper_id, coalesce(ts.summary, ''), coalesce(t.originally_available::text, ''), coalesce(e.originally_available::text, '')
    from tvshow_episode e
    join tvshow t on t.id = e.tvshow_id
    left join summary s on s.mapper_id = e.mapper_id
    left join summary ts on ts.mapper_id = t.mapper_id
    where e.season = ${Number(season)}
      and e.episode = ${Number(episode)}
      and (
        lower(t.title) = lower('${escaped}')
        or lower(replace(replace(t.title, ':', ''), '!', '')) = lower(replace(replace('${escaped}', ':', ''), '!', ''))
      )
    order by case when lower(t.title) = lower('${escaped}') then 0 else 1 end
    limit 1`);
  if (!rows) return null;
  const parts = rows.split("\t");
  if (parts.length < 7 || !parts[0]) return null;
  return applyEpisodeOverride({
    mapperId: parts[0],
    season: Number(parts[1]) || 0,
    episode: Number(parts[2]) || 0,
    episodeTitle: clean(parts[3]) || `Episode ${parts[2]}`,
    summary: parts[4] || "",
    showTitle: clean(parts[5]) || showTitle,
    showMapperId: parts[6],
    showSummary: parts[7] || "",
    showDate: /^\d{4}-\d{2}-\d{2}/.test(parts[8] || "") ? parts[8].slice(0, 10) : "",
    episodeDate: /^\d{4}-\d{2}-\d{2}/.test(parts[9] || "") ? parts[9].slice(0, 10) : "",
  });
}

function episodeInfoFromPath(videoPath) {
  const cleanPath = String(videoPath || "").replace(/\\/g, "/");
  const parts = cleanPath.split("/").filter(Boolean);
  const libraryIndex = parts.findIndex((part) => libraryNameForPart(part) !== "");
  if (libraryIndex < 0 || parts.length <= libraryIndex + 2) return null;
  const show = clean(parts[libraryIndex + 1]);
  const fileName = parts[parts.length - 1] || "";
  const baseName = withoutVideoExtension(fileName).replace(/[._]+/g, " ");
  const episodeMatch = baseName.match(/\bS(\d{1,2})E(\d{1,3})\b/i) || baseName.match(/\b(\d{1,2})x(\d{1,3})\b/i);
  if (!episodeMatch) return null;
  const season = Number(episodeMatch[1]) || 0;
  const episode = Number(episodeMatch[2]) || 0;
  if (!season || !episode) return null;

  let fileShow = "";
  if (episodeMatch.index > 0) fileShow = clean(baseName.slice(0, episodeMatch.index).replace(/[._-]+/g, " "));
  const outputShow = fileShow && normalizeForCompare(fileShow).length >= normalizeForCompare(show).length ? fileShow : show;
  let title = baseName;
  const showNorm = normalizeForCompare(outputShow);
  const titleNorm = normalizeForCompare(title);
  if (showNorm && titleNorm.startsWith(showNorm + " ")) title = title.slice(outputShow.length).trim();
  title = title.replace(/\bS\d{1,2}E\d{1,3}\b/i, " ");
  title = clean(title.replace(/[._]+/g, " ").replace(/^[-\s]+|[-\s]+$/g, ""));
  const dbEpisode = episodeInfoByShowSeasonEpisode(outputShow, season, episode) || episodeInfoByShowSeasonEpisode(show, season, episode);
  if (dbEpisode) {
    if (!dbEpisode.episodeTitle || dbEpisode.episodeTitle === `Episode ${episode}`) dbEpisode.episodeTitle = title || dbEpisode.episodeTitle;
    return dbEpisode;
  }
  const showInfo = showInfoByTitle(outputShow) || {};
  return applyEpisodeOverride({
    mapperId: "",
    season,
    episode,
    episodeTitle: title || `Episode ${episode}`,
    summary: "",
    showTitle: showInfo.showTitle || outputShow,
    showMapperId: showInfo.showMapperId || "",
    showSummary: showInfo.showSummary || "",
    showDate: showInfo.showDate || "",
    episodeDate: "",
  });
}

function movieInfo(videoPath) {
  const escaped = sqlEscape(videoPath);
  const rows = runSql(`
    select m.mapper_id, m.title, coalesce(s.summary, ''), coalesce(m.originally_available::text, ''), coalesce(m.year, 0)
    from video_file vf
    left join movie m on m.mapper_id = vf.mapper_id
    left join summary s on s.mapper_id = m.mapper_id
    where vf.path = '${escaped}' or vf.path like '%${sqlEscape(path.basename(videoPath))}'
    order by case when vf.path = '${escaped}' then 0 else 1 end
    limit 1`);
  if (!rows) return null;
  const parts = rows.split("\t");
  if (parts.length < 2 || !parts[0]) return null;
  return {
    mapperId: parts[0],
    title: clean(parts[1]),
    summary: parts[2] || "",
    releaseDate: /^\d{4}-\d{2}-\d{2}/.test(parts[3] || "") ? parts[3].slice(0, 10) : "",
    year: Number(parts[4]) || 0,
  };
}

function buildSeriesVsmeta(info, images) {
  const episodeImageChunks = imageTags(images.episode, 0x8a, 0x92, 1);
  const group3 = Buffer.concat(imageTags(images.backdrop, 0x0a, 0x12));
  const episodeDate = info.episodeDate || info.showDate || "";
  const group2Chunks = [
    tag(0x08, info.season, "int"),
    tag(0x10, info.episode, "int"),
    tag(0x18, episodeDate ? Number(episodeDate.slice(0, 4)) : 0, "int"),
  ];
  if (episodeDate) group2Chunks.push(tag(0x22, episodeDate, "date"));
  group2Chunks.push(tag(0x28, true, "bool"));
  if (info.showSummary) group2Chunks.push(tag(0x32, info.showSummary));
  group2Chunks.push(...imageTags(images.poster, 0x3a, 0x42));
  if (group3.length > 0) group2Chunks.push(tag(0x52, group3, "content"));

  return Buffer.concat([
    Buffer.from([0x08, 0x02]),
    tag(0x12, info.showTitle),
    tag(0x1a, info.showTitle),
    tag(0x22, info.episodeTitle),
    tag(0x38, true, "bool"),
    info.summary ? tag(0x42, info.summary) : Buffer.alloc(0),
    ...episodeImageChunks,
    Buffer.from([0x9a]),
    tag(0x01, Buffer.concat(group2Chunks), "content"),
  ]);
}

function buildMovieVsmeta(info, images) {
  const posterChunks = imageTags(images.poster, 0x8a, 0x92, 1);
  const group3 = Buffer.concat(imageTags(images.backdrop, 0x0a, 0x12));
  const chunks = [
    Buffer.from([0x08, 0x01]),
    tag(0x12, info.title),
    tag(0x1a, info.title),
    tag(0x22, info.title),
  ];
  if (info.year) chunks.push(tag(0x28, info.year, "int"));
  if (info.releaseDate) chunks.push(tag(0x32, info.releaseDate, "date"));
  chunks.push(tag(0x38, true, "bool"));
  if (info.summary) chunks.push(tag(0x42, info.summary));
  chunks.push(...posterChunks);
  if (group3.length > 0) {
    chunks.push(Buffer.from([0xaa]));
    chunks.push(tag(0x01, group3, "content"));
  }
  return Buffer.concat(chunks);
}

function generateOne(inputPath, outputVideoPath) {
  const outputPath = `${outputVideoPath}.vsmeta`;
  if (!force && fs.existsSync(outputPath)) return { action: "skip", reason: "exists", outputPath };

  const episode = episodeInfo(inputPath) || episodeInfoFromPath(inputPath);
  if (episode) {
    const images = {
      episode: imageFromTable("poster", episode.mapperId),
      poster: imageFromTable("poster", episode.showMapperId),
      backdrop: imageFromTable("backdrop", episode.showMapperId),
    };
    if (images.episode.length === 0) images.episode = generatedVideoPoster(inputPath);
    if (images.poster.length === 0) images.poster = images.episode;
    if (images.episode.length === 0) images.episode = images.poster;
    if (images.episode.length === 0) images.episode = images.backdrop;
    if (!dryRun) {
      fs.mkdirSync(path.dirname(outputPath), { recursive: true });
      fs.writeFileSync(outputPath, buildSeriesVsmeta(episode, images));
    }
    return {
      action: dryRun ? "would-write" : "write",
      type: "series",
      outputPath,
      title: episode.showTitle,
      season: episode.season,
      episode: episode.episode,
      episodeTitle: episode.episodeTitle,
      episodeImageBytes: images.episode.length,
      posterBytes: images.poster.length,
      backdropBytes: images.backdrop.length,
    };
  }

  const movie = movieInfo(inputPath);
  if (movie) {
    const images = {
      poster: imageFromTable("poster", movie.mapperId),
      backdrop: imageFromTable("backdrop", movie.mapperId),
    };
    if (images.poster.length === 0) images.poster = generatedVideoPoster(inputPath);
    if (!dryRun) {
      fs.mkdirSync(path.dirname(outputPath), { recursive: true });
      fs.writeFileSync(outputPath, buildMovieVsmeta(movie, images));
    }
    return {
      action: dryRun ? "would-write" : "write",
      type: "movie",
      outputPath,
      title: movie.title,
      posterBytes: images.poster.length,
      backdropBytes: images.backdrop.length,
    };
  }

  return { action: "skip", reason: "no movie/series metadata", inputPath, outputPath };
}

function allVideoPaths() {
  const max = limit > 0 ? `limit ${limit}` : "";
  const rows = runSql(`
    select vf.path
    from video_file vf
    where vf.path is not null
      and lower(vf.path) ~ '\\.(avi|mkv|mp4|m4v|mov|wmv|mpg|mpeg|ts|m2ts|webm)$'
    order by vf.path
    ${max}`);
  if (!rows) return [];
  return rows.split("\n").map((line) => line.trim()).filter(Boolean);
}

if (allMode) {
  const summary = { total: 0, write: 0, skip: 0, errors: 0 };
  for (const videoPath of allVideoPaths()) {
    summary.total += 1;
    try {
      const result = generateOne(videoPath, videoPath);
      if (result.action === "write" || result.action === "would-write") summary.write += 1;
      if (result.action === "skip") summary.skip += 1;
      console.log(JSON.stringify(result));
    } catch (err) {
      summary.errors += 1;
      console.log(JSON.stringify({ action: "error", inputPath: videoPath, error: err.message }));
    }
  }
  console.log(JSON.stringify({ summary, dryRun, force }));
} else {
  console.log(JSON.stringify(generateOne(sourcePath, targetVideoPath), null, 2));
}
