#!/usr/bin/env node
const fs = require("fs");
const readline = require("readline");
const zlib = require("zlib");
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
const APPLY = args.includes("--apply");
const limitArg = args.find((arg) => arg.startsWith("--limit="));
const LIMIT = limitArg ? Number(limitArg.split("=")[1]) || 0 : 0;
const basicsPath = argValue("--basics") || process.env.IMDB_BASICS || "/tmp/title.basics.tsv.gz";
const episodePath = argValue("--episodes") || process.env.IMDB_EPISODES || "/tmp/title.episode.tsv.gz";
const ratingsPath = argValue("--ratings") || process.env.IMDB_RATINGS || "/tmp/title.ratings.tsv.gz";

function argValue(name) {
  const found = args.find((arg) => arg === name || arg.startsWith(`${name}=`));
  if (!found) return "";
  if (found === name) return args[args.indexOf(found) + 1] || "";
  return found.slice(name.length + 1);
}

function sqlEscape(value) {
  return String(value || "").replace(/'/g, "''");
}

function runSql(sql) {
  const command = `psql -U VideoStation -d video_metadata -X -q -t -A -F "\t" -c "${sql.replace(/"/g, '\\"')}"`;
  const result = spawnSync("su", ["-l", "VideoStation", "-s", "/bin/bash", "-c", command], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 80,
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

function readRows(sql, mapper) {
  const output = runSql(sql);
  if (!output) return [];
  return output.split("\n").filter(Boolean).map((line) => mapper(line.split("\t")));
}

function targetMovies() {
  const max = LIMIT > 0 ? `limit ${LIMIT}` : "";
  return readRows(`
    select m.mapper_id, m.title, coalesce(m.year, 0), coalesce(m.originally_available::text, '')
    from movie m
    where coalesce(m.rating, 0) = 0
    order by m.title, m.year, m.mapper_id
    ${max}`, (p) => ({
      type: "movie",
      mapperId: Number(p[0]) || 0,
      title: p[1] || "",
      titleNorm: normalize(p[1]),
      year: Number(p[2]) || yearFromDate(p[3]),
    }));
}

function targetEpisodes() {
  const max = LIMIT > 0 ? `limit ${LIMIT}` : "";
  return readRows(`
    select e.mapper_id, t.title, coalesce(t.year, 0), e.season, e.episode, coalesce(e.tag_line, ''), coalesce(e.originally_available::text, '')
    from tvshow_episode e
    join tvshow t on t.id = e.tvshow_id
    where coalesce(e.rating, 0) = 0
    order by t.title, e.season, e.episode, e.mapper_id
    ${max}`, (p) => ({
      type: "episode",
      mapperId: Number(p[0]) || 0,
      showTitle: p[1] || "",
      showNorm: normalize(p[1]),
      showYear: Number(p[2]) || 0,
      season: Number(p[3]) || 0,
      episode: Number(p[4]) || 0,
      title: p[5] || "",
      titleNorm: normalize(p[5]),
      year: yearFromDate(p[6]),
    }));
}

function yearFromDate(value) {
  const match = String(value || "").match(/^(\d{4})/);
  return match ? Number(match[1]) : 0;
}

function assertFiles() {
  for (const file of [basicsPath, episodePath, ratingsPath]) {
    if (!fs.existsSync(file)) throw new Error(`missing IMDb dataset: ${file}`);
  }
}

async function readTsvGz(file, onRow) {
  const stream = fs.createReadStream(file).pipe(zlib.createGunzip());
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
  let header = [];
  for await (const line of rl) {
    if (!line) continue;
    const parts = line.split("\t");
    if (header.length === 0) {
      header = parts;
      continue;
    }
    const row = {};
    for (let i = 0; i < header.length; i += 1) row[header[i]] = parts[i] || "";
    await onRow(row);
  }
}

function candidateScore(target, candidate) {
  let score = 0;
  if (target.titleNorm && candidate.titleNorm === target.titleNorm) score += 50;
  if (target.type === "episode" && target.season === candidate.season && target.episode === candidate.episode) score += 40;
  if (target.year && candidate.year && Math.abs(target.year - candidate.year) <= 1) score += 5;
  if (target.showYear && candidate.showYear && Math.abs(target.showYear - candidate.showYear) <= 1) score += 5;
  return score;
}

function addCandidate(map, key, candidate) {
  if (!key) return;
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(candidate);
}

function chooseCandidate(target, candidates) {
  if (!candidates || candidates.length === 0) return null;
  const scored = candidates
    .map((candidate) => ({ candidate, score: candidateScore(target, candidate) }))
    .filter((item) => item.score >= (target.type === "movie" ? 50 : 40))
    .sort((a, b) => b.score - a.score || Number(b.candidate.votes || 0) - Number(a.candidate.votes || 0));
  if (scored.length === 0) return null;
  if (scored.length > 1 && scored[0].score === scored[1].score && scored[0].candidate.tconst !== scored[1].candidate.tconst) return null;
  return scored[0].candidate;
}

function updateRating(target, rating) {
  const table = target.type === "movie" ? "movie" : "tvshow_episode";
  runSql(`
    update ${table}
    set rating = ${Number(rating) || 0}, modify_date = now()
    where mapper_id = ${Number(target.mapperId)}
      and coalesce(rating, 0) = 0`);
}

async function main() {
  assertFiles();
  const movies = targetMovies();
  const episodes = targetEpisodes();
  const movieTitleSet = new Set(movies.map((row) => row.titleNorm).filter(Boolean));
  const showTitleSet = new Set(episodes.map((row) => row.showNorm).filter(Boolean));
  const episodeTitleSet = new Set(episodes.map((row) => row.titleNorm).filter(Boolean));
  const movieCandidates = new Map();
  const showCandidates = new Map();
  const episodeBasics = new Map();

  await readTsvGz(basicsPath, (row) => {
    const type = row.titleType || "";
    const primaryNorm = normalize(row.primaryTitle);
    const originalNorm = normalize(row.originalTitle);
    const year = Number(row.startYear) || 0;
    if ((type === "movie" || type === "tvMovie" || type === "video") && (movieTitleSet.has(primaryNorm) || movieTitleSet.has(originalNorm))) {
      const candidate = { tconst: row.tconst, titleNorm: primaryNorm, originalNorm, year };
      addCandidate(movieCandidates, primaryNorm, candidate);
      addCandidate(movieCandidates, originalNorm, candidate);
    }
    if ((type === "tvSeries" || type === "tvMiniSeries") && (showTitleSet.has(primaryNorm) || showTitleSet.has(originalNorm))) {
      const candidate = { tconst: row.tconst, titleNorm: primaryNorm, originalNorm, showYear: year };
      addCandidate(showCandidates, primaryNorm, candidate);
      addCandidate(showCandidates, originalNorm, candidate);
    }
    if (type === "tvEpisode" && (episodeTitleSet.has(primaryNorm) || episodeTitleSet.has(originalNorm))) {
      episodeBasics.set(row.tconst, { tconst: row.tconst, titleNorm: primaryNorm, originalNorm, year });
    }
  });

  const showTconstToTargets = new Map();
  for (const target of episodes) {
    for (const show of showCandidates.get(target.showNorm) || []) {
      if (!showTconstToTargets.has(show.tconst)) showTconstToTargets.set(show.tconst, []);
      showTconstToTargets.get(show.tconst).push({ target, show });
    }
  }

  const episodeCandidates = new Map();
  await readTsvGz(episodePath, (row) => {
    const targetShows = showTconstToTargets.get(row.parentTconst);
    if (!targetShows) return;
    const basics = episodeBasics.get(row.tconst) || { tconst: row.tconst, titleNorm: "", originalNorm: "", year: 0 };
    const candidate = {
      ...basics,
      season: Number(row.seasonNumber) || 0,
      episode: Number(row.episodeNumber) || 0,
      parentTconst: row.parentTconst,
    };
    for (const { target, show } of targetShows) {
      if ((candidate.season === target.season && candidate.episode === target.episode) || candidate.titleNorm === target.titleNorm || candidate.originalNorm === target.titleNorm) {
        if (!episodeCandidates.has(target.mapperId)) episodeCandidates.set(target.mapperId, []);
        episodeCandidates.get(target.mapperId).push({ ...candidate, showYear: show.showYear });
      }
    }
  });

  const wantedTconsts = new Set();
  const chosen = [];
  for (const target of movies) {
    const candidate = chooseCandidate(target, movieCandidates.get(target.titleNorm));
    if (candidate) {
      chosen.push({ target, candidate });
      wantedTconsts.add(candidate.tconst);
    }
  }
  for (const target of episodes) {
    const candidate = chooseCandidate(target, episodeCandidates.get(target.mapperId));
    if (candidate) {
      chosen.push({ target, candidate });
      wantedTconsts.add(candidate.tconst);
    }
  }

  const ratings = new Map();
  await readTsvGz(ratingsPath, (row) => {
    if (wantedTconsts.has(row.tconst)) ratings.set(row.tconst, { average: Number(row.averageRating) || 0, votes: Number(row.numVotes) || 0 });
  });

  const summary = { dryRun: !APPLY, movies: movies.length, episodes: episodes.length, matched: 0, updated: 0, skippedNoRating: 0 };
  for (const item of chosen) {
    const rating = ratings.get(item.candidate.tconst);
    if (!rating || !rating.average) {
      summary.skippedNoRating += 1;
      continue;
    }
    const value = Math.round(rating.average * 10);
    summary.matched += 1;
    const label = item.target.type === "movie"
      ? item.target.title
      : `${item.target.showTitle} S${String(item.target.season).padStart(2, "0")}E${String(item.target.episode).padStart(2, "0")} ${item.target.title}`;
    console.log(JSON.stringify({ action: APPLY ? "update" : "would-update", type: item.target.type, mapperId: item.target.mapperId, title: label, tconst: item.candidate.tconst, rating: value, imdbAverage: rating.average, votes: rating.votes }));
    if (APPLY) {
      updateRating(item.target, value);
      summary.updated += 1;
    }
  }
  console.log(JSON.stringify({ action: "summary", ...summary }));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
