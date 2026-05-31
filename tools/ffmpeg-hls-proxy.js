#!/usr/bin/env node
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { spawn } = require("child_process");

const HOST = process.env.ROKU_HLS_HOST || "0.0.0.0";
const PORT = Number(process.env.ROKU_HLS_PORT || 8099);
const BASE_URL = process.env.ROKU_HLS_BASE_URL || `http://127.0.0.1:${PORT}`;
const PATH_PREFIX = (process.env.ROKU_HLS_PATH_PREFIX || "").replace(/\/+$/, "");
const ROOT = process.env.ROKU_HLS_ROOT || path.join("/private/tmp", "roku-hls-proxy");
const FFMPEG = process.env.FFMPEG || "ffmpeg";
const AUDIO_CODEC = process.env.ROKU_HLS_AUDIO_CODEC || "libmp3lame";
const HTTPS_KEY = process.env.ROKU_HLS_HTTPS_KEY || "";
const HTTPS_CERT = process.env.ROKU_HLS_HTTPS_CERT || "";
const START_SEGMENTS = Number(process.env.ROKU_HLS_START_SEGMENTS || 6);

fs.mkdirSync(ROOT, { recursive: true });

const sessions = new Map();

function send(res, status, headers, body) {
  res.writeHead(status, headers);
  res.end(body);
}

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runVideoStationSql(sql, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const command = `psql -U VideoStation -d video_metadata -X -q -t -A -c "${sql.replace(/"/g, '\\"')}"`;
    const child = spawn("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error("metadata query timeout"));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("exit", (code) => {
      clearTimeout(timer);
      if (code !== 0) return reject(new Error(stderr.trim() || `psql exited ${code}`));
      resolve(stdout.trim());
    });
  });
}

async function tvMetadata(title) {
  const escapedTitle = sqlEscape(title);
  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.season, x.episode), '[]'::json)
    from (
      select *
      from (
        select
        e.season,
        e.episode,
        e.tag_line as title,
        coalesce(s.summary, '') as summary,
        vf.path as path,
        e.mapper_id,
        e.id,
        t.mapper_id as show_mapper_id,
        row_number() over (
          partition by e.id
          order by
            case when lower(coalesce(vf.path, '')) like '%short%' or lower(coalesce(vf.path, '')) like '%extra%' then 1 else 0 end,
            vf.path
        ) as rn
      from tvshow t
      join tvshow_episode e on e.tvshow_id = t.id
      left join summary s on s.mapper_id = e.mapper_id
      left join video_file vf on vf.mapper_id = e.mapper_id
      where lower(t.title) = lower('${escapedTitle}')
      ) ranked
      where rn = 1
    ) x`;
  const output = await runVideoStationSql(sql);
  return output || "[]";
}

async function tvEpisodes(tvshowId, title) {
  const safeId = String(tvshowId || "").replace(/[^0-9]/g, "");
  const escapedTitle = sqlEscape(title);
  const conditions = [];
  if (safeId) {
    conditions.push(`t.id = ${safeId}`);
    conditions.push(`t.mapper_id = ${safeId}`);
  }
  if (escapedTitle) conditions.push(`lower(t.title) = lower('${escapedTitle}')`);
  if (conditions.length === 0) return "[]";

  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.season, x.episode, x.path), '[]'::json)
    from (
      select *
      from (
        select
          e.id,
          e.mapper_id,
          t.mapper_id as show_mapper_id,
          e.season,
          e.episode,
          e.tag_line as title,
          e.tag_line as name,
          coalesce(s.summary, '') as summary,
          coalesce(s.summary, '') as description,
          vf.path as path,
          json_build_object(
            'file',
            json_build_array(json_build_object('id', vf.id, 'path', vf.path))
          ) as additional,
          row_number() over (
            partition by e.id
            order by
              case when lower(coalesce(vf.path, '')) like '%short%' or lower(coalesce(vf.path, '')) like '%extra%' then 1 else 0 end,
              vf.path
          ) as rn
        from tvshow t
        join tvshow_episode e on e.tvshow_id = t.id
        left join summary s on s.mapper_id = e.mapper_id
        left join video_file vf on vf.mapper_id = e.mapper_id
        where (${conditions.join(" or ")})
          and vf.path is not null
      ) ranked
      where rn = 1
    ) x`;
  const output = await runVideoStationSql(sql);
  return output || "[]";
}

async function libraries() {
  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.id), '[]'::json)
    from (
      select id, title, type
      from library
      where is_public = true
      order by id
    ) x`;
  const output = await runVideoStationSql(sql);
  return output || "[]";
}

async function posterBuffer(mapperId, fallbackMapperId = "") {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) throw new Error("missing mapper_id");
  const sql = `select encode(lo_get(lo_oid), 'base64') from poster where mapper_id = ${safeId} limit 1`;
  const output = await runVideoStationSql(sql);
  if (!output) {
    const generated = await generatedVideoPosterBuffer(safeId);
    if (generated) return generated;
    const safeFallback = String(fallbackMapperId || "").replace(/[^0-9]/g, "");
    if (safeFallback) return backdropBuffer(safeFallback);
    throw new Error("poster not found");
  }
  return Buffer.from(output.replace(/\s+/g, ""), "base64");
}

async function generatedVideoPosterBuffer(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return null;
  const sql = `select path from video_file where mapper_id = ${safeId} order by id limit 1`;
  const videoPath = await runVideoStationSql(sql);
  if (!videoPath) return null;

  const dir = path.dirname(videoPath);
  const base = path.basename(videoPath);
  const thumbDir = path.join(dir, "@eaDir", base);
  const candidates = [
    path.join(thumbDir, "SYNOVIDEO_VIDEO_POSTER.jpg"),
    path.join(thumbDir, "SYNOVIDEO_VIDEO_POSTER_JPEGTN.jpg"),
    path.join(thumbDir, "SYNOVIDEO_VIDEO_SCREENSHOT.jpg"),
    path.join(thumbDir, "SYNOVIDEO_VIDEO_SCREENSHOT_JPEGTN.jpg"),
  ];

  for (const candidate of candidates) {
    try {
      if (fs.existsSync(candidate)) return fs.readFileSync(candidate);
    } catch {
      // Try the next generated thumbnail candidate.
    }
  }
  return null;
}

async function backdropBuffer(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) throw new Error("missing mapper_id");
  const sql = `select encode(lo_get(lo_oid), 'base64') from backdrop where mapper_id = ${safeId} limit 1`;
  const output = await runVideoStationSql(sql);
  if (!output) {
    const showMapperId = await showMapperIdForEpisode(safeId);
    if (showMapperId && showMapperId !== safeId) return backdropBuffer(showMapperId);
    throw new Error("backdrop not found");
  }
  return Buffer.from(output.replace(/\s+/g, ""), "base64");
}

async function showMapperIdForEpisode(mapperId) {
  const safeId = String(mapperId || "").replace(/[^0-9]/g, "");
  if (!safeId) return "";
  const sql = `
    select t.mapper_id
    from tvshow_episode e
    join tvshow t on t.id = e.tvshow_id
    where e.mapper_id = ${safeId} or e.id = ${safeId}
    limit 1`;
  return await runVideoStationSql(sql);
}

async function libraryItems(libraryId, type) {
  const safeLibraryId = String(libraryId || "").replace(/[^0-9]/g, "");

  const normalizedType = String(type || "").toLowerCase();
  let table = "";
  if (normalizedType === "movie") table = "movie";
  if (normalizedType === "tvshow") table = "tvshow";
  if (normalizedType === "homevideo" || normalizedType === "home_video") table = "home_video";
  if (!table) return "[]";

  const dateExpr = table === "home_video" ? "record_time::text" : "originally_available::text";
  const yearExpr = table === "home_video" ? "extract(year from record_time)::int" : "year";
  const libraryWhere = safeLibraryId ? `library_id = ${safeLibraryId}` : "library_id is null";
  const sql = `
    select coalesce(json_agg(row_to_json(x) order by x.sort_title, x.title), '[]'::json)
    from (
      select id, mapper_id, title, sort_title, library_id, ${yearExpr} as year, ${dateExpr} as original_available
      from ${table}
      where ${libraryWhere}
      order by sort_title, title
    ) x`;
  const output = await runVideoStationSql(sql);
  return output || "[]";
}

function pipeSourceToFfmpeg(src, child, id, redirectCount = 0) {
  let srcUrl;
  try {
    srcUrl = new URL(src);
  } catch (err) {
    child.stdin.destroy(err);
    return;
  }

  const client = srcUrl.protocol === "https:" ? https : http;
  const req = client.get(srcUrl, { rejectUnauthorized: false }, (res) => {
    if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && redirectCount < 5) {
      res.resume();
      const next = new URL(res.headers.location, srcUrl).toString();
      pipeSourceToFfmpeg(next, child, id, redirectCount + 1);
      return;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      console.log(`[proxy] source http ${id} status=${res.statusCode}`);
      res.resume();
      child.stdin.destroy(new Error(`source status ${res.statusCode}`));
      return;
    }

    res.pipe(child.stdin);
  });

  req.on("error", (err) => {
    console.log(`[proxy] source error ${id} ${err.message}`);
    child.stdin.destroy(err);
  });
}

function sessionFor(src) {
  const id = crypto.createHash("sha1").update(src).digest("hex").slice(0, 16);
  let session = sessions.get(id);
  if (session) return session;

  const dir = path.join(ROOT, id);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  const playlist = path.join(dir, "index.m3u8");
  const args = [
    "-hide_banner",
    "-loglevel", "warning",
    "-fflags", "+genpts",
    "-i", "pipe:0",
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-profile:v", "high",
    "-level", "4.0",
    "-pix_fmt", "yuv420p",
    "-g", "120",
    "-keyint_min", "120",
    "-sc_threshold", "0",
    "-force_key_frames", "expr:gte(t,n_forced*4)",
    "-vf", "scale='min(1280,iw)':-2",
    "-c:a", AUDIO_CODEC,
    "-ac", "2",
    "-b:a", "160k",
    "-max_muxing_queue_size", "1024",
    "-avoid_negative_ts", "make_zero",
    "-f", "hls",
    "-hls_time", "4",
    "-hls_list_size", "0",
    "-hls_flags", "independent_segments+omit_endlist",
    "-hls_segment_filename", path.join(dir, "seg_%05d.ts"),
    playlist,
  ];

  console.log(`[proxy] start ${id}`);
  const child = spawn(FFMPEG, args, { stdio: ["pipe", "ignore", "pipe"] });
  child.stdin.on("error", (err) => {
    console.log(`[proxy] stdin error ${id} ${err.code || err.message}`);
  });
  pipeSourceToFfmpeg(src, child, id);
  child.stderr.on("data", (chunk) => {
    const text = chunk.toString().trim();
    if (text) console.log(`[ffmpeg ${id}] ${text}`);
  });
  child.on("exit", (code, signal) => {
    console.log(`[proxy] ffmpeg exit ${id} code=${code} signal=${signal}`);
    const s = sessions.get(id);
    if (s) {
      s.exited = true;
      s.exitCode = code;
      s.signal = signal;
    }
  });

  session = { id, src, dir, playlist, child, createdAt: Date.now(), exited: false };
  sessions.set(id, session);
  return session;
}

function waitForPlaylist(file, deadlineMs) {
  return new Promise((resolve) => {
    const started = Date.now();
    const tick = () => {
      if (fs.existsSync(file) && fs.statSync(file).size > 0) return resolve(true);
      if (Date.now() - started >= deadlineMs) return resolve(false);
      setTimeout(tick, 250);
    };
    tick();
  });
}

function readySegmentCount(session) {
  let count = 0;
  for (let i = 0; i < START_SEGMENTS; i += 1) {
    const file = path.join(session.dir, `seg_${String(i).padStart(5, "0")}.ts`);
    if (fs.existsSync(file) && fs.statSync(file).size > 0) count += 1;
  }
  return count;
}

function waitForInitialSegments(session, deadlineMs) {
  return new Promise((resolve) => {
    const started = Date.now();
    const tick = () => {
      const count = readySegmentCount(session);
      if (count >= START_SEGMENTS) return resolve(true);
      if (Date.now() - started >= deadlineMs) return resolve(count > 0);
      setTimeout(tick, 250);
    };
    tick();
  });
}

function publicBaseUrl(req) {
  if (process.env.ROKU_HLS_BASE_URL) return process.env.ROKU_HLS_BASE_URL;
  const forwardedProto = (req.headers["x-forwarded-proto"] || "").split(",")[0].trim();
  const forwardedHost = (req.headers["x-forwarded-host"] || "").split(",")[0].trim();
  const proto = forwardedProto || (req.socket.encrypted ? "https" : "http");
  const host = forwardedHost || req.headers.host || `127.0.0.1:${PORT}`;
  return `${proto}://${host}${PATH_PREFIX}`;
}

function rewritePlaylist(session, req) {
  const base = publicBaseUrl(req);
  let text = fs.readFileSync(session.playlist, "utf8");
  text = text.replace(/^(seg_\d+\.ts)$/gm, `${base}/hls/${session.id}/$1`);
  return text;
}

async function handleRequest(req, res) {
  const url = new URL(req.url, BASE_URL);
  let requestPath = url.pathname;
  if (PATH_PREFIX && requestPath.startsWith(PATH_PREFIX + "/")) {
    requestPath = requestPath.slice(PATH_PREFIX.length);
  }

  if (requestPath === "/health") {
    return send(res, 200, { "content-type": "application/json" }, JSON.stringify({ ok: true, sessions: sessions.size }));
  }

  if (requestPath === "/tvmeta") {
    const title = url.searchParams.get("title") || "";
    if (!title) return send(res, 400, { "content-type": "application/json" }, JSON.stringify({ success: false, error: "missing title" }));
    try {
      const items = await tvMetadata(title);
      return send(res, 200, { "content-type": "application/json", "cache-control": "no-store" }, JSON.stringify({ success: true, items: JSON.parse(items) }));
    } catch (err) {
      console.log(`[proxy] tvmeta error ${err.message}`);
      return send(res, 500, { "content-type": "application/json" }, JSON.stringify({ success: false, error: err.message }));
    }
  }

  if (requestPath === "/episodes") {
    const tvshowId = url.searchParams.get("tvshow_id") || "";
    const title = url.searchParams.get("title") || "";
    try {
      const items = await tvEpisodes(tvshowId, title);
      return send(res, 200, { "content-type": "application/json", "cache-control": "no-store" }, JSON.stringify({ success: true, items: JSON.parse(items) }));
    } catch (err) {
      console.log(`[proxy] episodes error ${err.message}`);
      return send(res, 500, { "content-type": "application/json" }, JSON.stringify({ success: false, error: err.message }));
    }
  }

  if (requestPath === "/libraries") {
    try {
      const items = await libraries();
      return send(res, 200, { "content-type": "application/json", "cache-control": "no-store" }, JSON.stringify({ success: true, items: JSON.parse(items) }));
    } catch (err) {
      console.log(`[proxy] libraries error ${err.message}`);
      return send(res, 500, { "content-type": "application/json" }, JSON.stringify({ success: false, error: err.message }));
    }
  }

  if (requestPath === "/libraryitems") {
    const libraryId = url.searchParams.get("library_id") || "";
    const type = url.searchParams.get("type") || "";
    try {
      const items = await libraryItems(libraryId, type);
      return send(res, 200, { "content-type": "application/json", "cache-control": "no-store" }, JSON.stringify({ success: true, items: JSON.parse(items) }));
    } catch (err) {
      console.log(`[proxy] libraryitems error ${err.message}`);
      return send(res, 500, { "content-type": "application/json" }, JSON.stringify({ success: false, error: err.message }));
    }
  }

  if (requestPath === "/poster") {
    const mapperId = url.searchParams.get("mapper_id") || url.searchParams.get("mapper") || "";
    const fallbackMapperId = url.searchParams.get("fallback_mapper_id") || "";
    try {
      const image = await posterBuffer(mapperId, fallbackMapperId);
      return send(res, 200, {
        "content-type": "image/jpeg",
        "content-length": String(image.length),
        "cache-control": "public, max-age=2592000, immutable",
      }, image);
    } catch (err) {
      console.log(`[proxy] poster error mapper=${mapperId} fallback=${fallbackMapperId} ${err.message}`);
      return send(res, 404, { "content-type": "text/plain" }, "poster not found");
    }
  }

  if (requestPath === "/backdrop") {
    const mapperId = url.searchParams.get("mapper_id") || url.searchParams.get("mapper") || "";
    try {
      const image = await backdropBuffer(mapperId);
      return send(res, 200, {
        "content-type": "image/jpeg",
        "content-length": String(image.length),
        "cache-control": "public, max-age=2592000, immutable",
      }, image);
    } catch (err) {
      console.log(`[proxy] backdrop error mapper=${mapperId} ${err.message}`);
      return send(res, 404, { "content-type": "text/plain" }, "backdrop not found");
    }
  }

  if (requestPath === "/transcode") {
    const src = url.searchParams.get("src");
    if (!src) return send(res, 400, { "content-type": "text/plain" }, "missing src");
    const session = sessionFor(src);
    const ready = await waitForPlaylist(session.playlist, 20000);
    if (!ready) return send(res, 504, { "content-type": "text/plain" }, "playlist not ready");
    const segmentsReady = await waitForInitialSegments(session, 30000);
    if (!segmentsReady) return send(res, 504, { "content-type": "text/plain" }, "segments not ready");
    console.log(`[proxy] playlist ${session.id}`);
    return send(res, 200, {
      "content-type": "application/vnd.apple.mpegurl",
      "cache-control": "no-store",
    }, rewritePlaylist(session, req));
  }

  const match = requestPath.match(/^\/hls\/([a-f0-9]{16})\/(.+)$/);
  if (match) {
    const [, id, name] = match;
    const session = sessions.get(id);
    if (!session) return send(res, 404, { "content-type": "text/plain" }, "unknown session");
    const file = path.join(session.dir, path.basename(name));
    if (!fs.existsSync(file)) return send(res, 404, { "content-type": "text/plain" }, "not ready");
    console.log(`[proxy] segment ${id}/${path.basename(name)}`);
    const type = name.endsWith(".m3u8") ? "application/vnd.apple.mpegurl" : "video/mp2t";
    res.writeHead(200, { "content-type": type, "cache-control": "no-store" });
    fs.createReadStream(file).pipe(res);
    return;
  }

  send(res, 404, { "content-type": "text/plain" }, "not found");
}

function createServer() {
  if (HTTPS_KEY && HTTPS_CERT) {
    return https.createServer({
      key: fs.readFileSync(HTTPS_KEY),
      cert: fs.readFileSync(HTTPS_CERT),
    }, handleRequest);
  }

  return http.createServer(handleRequest);
}

const server = createServer();

server.listen(PORT, HOST, () => {
  if (HTTPS_KEY && HTTPS_CERT) {
    console.log(`[proxy] listening on https://127.0.0.1:${PORT}`);
  } else {
    console.log(`[proxy] listening on ${BASE_URL}`);
  }
  console.log(`[proxy] temp root ${ROOT}`);
});
