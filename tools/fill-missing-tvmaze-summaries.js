#!/usr/bin/env node
const https = require("https");
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
const APPLY = args.includes("--apply");
const limitArg = args.find((arg) => arg.startsWith("--limit="));
const LIMIT = limitArg ? Number(limitArg.split("=")[1]) || 0 : 0;
const delayArg = args.find((arg) => arg.startsWith("--delay-ms="));
const DELAY_MS = delayArg ? Number(delayArg.split("=")[1]) || 0 : 250;

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runSql(sql) {
  const command = `psql -U VideoStation -d video_metadata -X -q -t -A -F "\t" -c "${sql.replace(/"/g, '\\"')}"`;
  const result = spawnSync("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 40,
  });
  if (result.status !== 0) throw new Error((result.stderr || result.stdout || `psql failed ${result.status}`).trim());
  return String(result.stdout || "").trim();
}

function normalize(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function stripHtml(value) {
  return String(value || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&ldquo;/g, '"')
    .replace(/&rdquo;/g, '"')
    .replace(/&nbsp;/g, " ")
    .replace(/\s+\n/g, "\n")
    .replace(/\n\s+/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function rows(sql, mapper) {
  const output = runSql(sql);
  if (!output) return [];
  return output.split("\n").filter(Boolean).map((line) => mapper(line.split("\t")));
}

function missingShows() {
  const max = LIMIT > 0 ? `limit ${LIMIT}` : "";
  return rows(`
    select t.id, t.mapper_id, t.title, coalesce(t.year, 0), coalesce(t.originally_available::text, '')
    from tvshow t
    left join summary s on s.mapper_id = t.mapper_id
    where coalesce(s.summary, '') = ''
    order by t.title
    ${max}`, (p) => ({
      id: Number(p[0]) || 0,
      mapperId: Number(p[1]) || 0,
      title: p[2] || "",
      norm: normalize(p[2]),
      year: Number(p[3]) || yearFromDate(p[4]),
    }));
}

function missingEpisodes() {
  const max = LIMIT > 0 ? `limit ${LIMIT}` : "";
  return rows(`
    select e.mapper_id, t.title, coalesce(t.year, 0), e.season, e.episode, coalesce(e.tag_line, '')
    from tvshow_episode e
    join tvshow t on t.id = e.tvshow_id
    left join summary s on s.mapper_id = e.mapper_id
    where coalesce(s.summary, '') = ''
    order by t.title, e.season, e.episode, e.mapper_id
    ${max}`, (p) => ({
      mapperId: Number(p[0]) || 0,
      showTitle: p[1] || "",
      showNorm: normalize(p[1]),
      showYear: Number(p[2]) || 0,
      season: Number(p[3]) || 0,
      episode: Number(p[4]) || 0,
      title: p[5] || "",
    }));
}

function yearFromDate(value) {
  const match = String(value || "").match(/^(\d{4})/);
  return match ? Number(match[1]) : 0;
}

function httpJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { "User-Agent": "roku-ds-video-tools/1.0" } }, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => { body += chunk; });
      res.on("end", () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          resolve(null);
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    }).on("error", reject);
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function tvmazeShow(title) {
  const url = `https://api.tvmaze.com/singlesearch/shows?q=${encodeURIComponent(title)}&embed=episodes`;
  const data = await httpJson(url);
  if (!data || !data.name) return null;
  if (DELAY_MS > 0) await sleep(DELAY_MS);
  return data;
}

function showMatches(local, remote) {
  if (!remote) return false;
  if (normalize(remote.name) !== local.norm) return false;
  const remoteYear = yearFromDate(remote.premiered);
  if (local.year && remoteYear && Math.abs(local.year - remoteYear) > 2) return false;
  return true;
}

function upsertSummary(mapperId, summary) {
  runSql(`
    with updated as (
      update summary
      set summary = '${sqlEscape(summary)}', modify_date = now()
      where mapper_id = ${Number(mapperId)}
        and coalesce(summary, '') = ''
      returning 1
    )
    insert into summary(mapper_id, summary, create_date, modify_date)
    select ${Number(mapperId)}, '${sqlEscape(summary)}', now(), now()
    where not exists (select 1 from summary where mapper_id = ${Number(mapperId)})`);
}

async function main() {
  const shows = missingShows();
  const episodes = missingEpisodes();
  const showMap = new Map();
  for (const show of shows) showMap.set(show.norm, show);
  for (const episode of episodes) {
    if (!showMap.has(episode.showNorm)) {
      showMap.set(episode.showNorm, { title: episode.showTitle, norm: episode.showNorm, year: episode.showYear, mapperId: 0 });
    }
  }

  const summary = { dryRun: !APPLY, shows: shows.length, episodes: episodes.length, matchedShows: 0, matchedEpisodes: 0, updated: 0, skipped: 0 };
  for (const localShow of showMap.values()) {
    const remote = await tvmazeShow(localShow.title);
    if (!showMatches(localShow, remote)) {
      console.log(JSON.stringify({ action: "skip", reason: "show-match", title: localShow.title, remote: remote?.name || "" }));
      summary.skipped += 1;
      continue;
    }
    summary.matchedShows += 1;
    const remoteEpisodes = (((remote || {})._embedded || {}).episodes || []);
    const showSummary = stripHtml(remote.summary);
    const showTarget = shows.find((row) => row.norm === localShow.norm && row.mapperId);
    if (showTarget && showSummary) {
      console.log(JSON.stringify({ action: APPLY ? "update" : "would-update", type: "show", mapperId: showTarget.mapperId, title: showTarget.title, source: "tvmaze" }));
      if (APPLY) upsertSummary(showTarget.mapperId, showSummary);
      summary.updated += APPLY ? 1 : 0;
    }
    for (const localEpisode of episodes.filter((row) => row.showNorm === localShow.norm)) {
      const remoteEpisode = remoteEpisodes.find((row) => Number(row.season) === localEpisode.season && Number(row.number) === localEpisode.episode);
      const episodeSummary = stripHtml(remoteEpisode?.summary || "");
      if (!episodeSummary) {
        summary.skipped += 1;
        continue;
      }
      console.log(JSON.stringify({
        action: APPLY ? "update" : "would-update",
        type: "episode",
        mapperId: localEpisode.mapperId,
        title: `${localEpisode.showTitle} S${String(localEpisode.season).padStart(2, "0")}E${String(localEpisode.episode).padStart(2, "0")} ${localEpisode.title}`,
        source: "tvmaze",
      }));
      summary.matchedEpisodes += 1;
      if (APPLY) {
        upsertSummary(localEpisode.mapperId, episodeSummary);
        summary.updated += 1;
      }
    }
  }
  console.log(JSON.stringify({ action: "summary", ...summary }));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
