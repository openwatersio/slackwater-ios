#!/usr/bin/env node
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const end = new Date("2026-09-01T00:00:00Z");
const targets = [
  { key: "victoria", name: "Victoria Harbour", latitude: 48.424363, longitude: -123.370828, days: 60, codes: ["wlp"] },
  { key: "active", name: "Active Pass", latitude: 48.8604, longitude: -123.3128, days: 60, codes: ["wcsp1", "wcdp1"], metadata: true },
  { key: "dodd", name: "Dodd Narrows", latitude: 49.135466, longitude: -123.817351, days: 210, codes: ["wcsp1", "wcdp1"], metadata: true },
  { key: "sechelt", name: "Sechelt Rapids", latitude: 49.7383, longitude: -123.8983, days: 10, codes: ["wcsp1", "wcdp1"], metadata: true },
];

function defaultFixtureDir() {
  const common = execFileSync("rtk", ["git", "rev-parse", "--git-common-dir"], { cwd: root, encoding: "utf8" }).trim();
  return resolve(root, common, "..", ".test-fixtures", "iwls");
}

function paths(fixtureDir = process.env.SLACKWATER_FIXTURE_DIR || defaultFixtureDir(), staged = join(root, "SlackwaterTests/Fixtures/iwls-recording.json")) {
  return { fixtureDir, recording: join(fixtureDir, "iwls-recording.json"), staged };
}

export function validate(recording) {
  if (recording?.schemaVersion !== 1 || !recording.capturedAt || recording?.bounds?.end !== end.toISOString())
    throw new Error("recording has an unsupported schema or bounds");
  for (const target of targets) {
    const station = recording.stations?.find((item) => item.key === target.key);
    if (!station?.id || !Number.isFinite(station.latitude) || !Number.isFinite(station.longitude))
      throw new Error(`${target.key}: station metadata is missing`);
    if (target.metadata && (!Number.isFinite(station.metadata?.floodDirection) || !Number.isFinite(station.metadata?.ebbDirection)))
      throw new Error(`${target.key}: current directions are missing`);
    for (const code of target.codes) {
      const samples = station.series?.[code];
      if (!Array.isArray(samples) || !samples.length || samples.some((sample) => !Number.isFinite(sample.value) || !Date.parse(sample.eventDate)))
        throw new Error(`${target.key}: ${code} has no valid samples`);
      const times = samples.map((sample) => Date.parse(sample.eventDate));
      if (new Set(times).size !== times.length || times.length < target.days * 80 ||
          Math.min(...times) > end.getTime() - (target.days * 86_400_000) + 86_400_000 ||
          Math.max(...times) < end.getTime() - 86_400_000)
        throw new Error(`${target.key}: ${code} does not cover the expected ${target.days}-day window`);
    }
  }
  return recording;
}

export async function prepare(options = {}) {
  const { recording, staged } = paths(options.fixtureDir, options.staged);
  let parsed;
  try { parsed = JSON.parse(await readFile(recording, "utf8")); }
  catch (error) {
    if (error.code === "ENOENT") throw new Error(`IWLS recording missing at ${recording}; run: node scripts/iwls-fixtures.mjs refresh`);
    throw new Error(`IWLS recording at ${recording} is not valid JSON: ${error.message}`);
  }
  validate(parsed);
  await mkdir(dirname(staged), { recursive: true });
  await writeFile(staged, `${JSON.stringify(parsed)}\n`);
  return staged;
}

export async function refresh(options = {}) {
  const { fixtureDir, recording } = paths(options.fixtureDir);
  const fetchImpl = options.fetchImpl || fetch;
  const paceMs = options.paceMs ?? 2500;
  const api = options.api || process.env.IWLS_API_BASE || "https://api-iwls.dfo-mpo.gc.ca/api/v1";
  let last = 0;
  async function get(path) {
    const wait = paceMs - (Date.now() - last);
    if (wait > 0) await new Promise((done) => setTimeout(done, wait));
    last = Date.now();
    const response = await fetchImpl(api + path, { signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
    return response.json();
  }
  const catalog = await get("/stations");
  const stations = [];
  for (const target of targets) {
    const candidates = catalog.filter((item) => target.codes.every((code) => item.timeSeries.some((series) => series.code === code)));
    const distance = (item) => {
      const dLat = (item.latitude - target.latitude) * Math.PI / 180;
      const dLon = (item.longitude - target.longitude) * Math.PI / 180;
      const a = Math.sin(dLat / 2) ** 2 + Math.cos(target.latitude * Math.PI / 180) * Math.cos(item.latitude * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
      return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    };
    const station = candidates.sort((a, b) => distance(a) - distance(b))[0];
    if (station && distance(station) > 3) throw new Error(`${target.name}: nearest IWLS station is ${distance(station).toFixed(1)} km away`);
    if (!station) throw new Error(`${target.name}: station not found in IWLS catalog`);
    const available = new Set(station.timeSeries.map((item) => item.code));
    for (const code of target.codes) if (!available.has(code)) throw new Error(`${target.name}: IWLS catalog has no ${code}`);
    const entry = { key: target.key, id: station.id, officialName: station.officialName,
      latitude: station.latitude, longitude: station.longitude,
      metadata: target.metadata ? await get(`/stations/${station.id}/metadata`) : null, series: {} };
    for (const code of target.codes) {
      if (options.progress !== false) console.error(`Recording ${target.name} ${code} (${target.days} d)…`);
      const samples = [];
      for (let to = end; to > new Date(end.getTime() - target.days * 86_400_000);) {
        const from = new Date(Math.max(to.getTime() - 7 * 86_400_000, end.getTime() - target.days * 86_400_000));
        const query = new URLSearchParams({ "time-series-code": code, from: from.toISOString(), to: to.toISOString() });
        samples.unshift(...await get(`/stations/${station.id}/data?${query}`));
        to = from;
      }
      const unique = [...new Map(samples.map((sample) => [sample.eventDate, sample])).values()];
      if (code === "wlp") {
        const offGrid = unique.find((sample) => Date.parse(sample.eventDate) % 900_000 !== 0);
        entry.series[code] = unique.filter((sample) => Date.parse(sample.eventDate) % 900_000 === 0);
        if (offGrid) entry.series[code].push(offGrid);
        entry.series[code].sort((a, b) => Date.parse(a.eventDate) - Date.parse(b.eventDate));
      } else entry.series[code] = unique.sort((a, b) => Date.parse(a.eventDate) - Date.parse(b.eventDate));
    }
    stations.push(entry);
  }
  const result = validate({ schemaVersion: 1, capturedAt: new Date().toISOString(), bounds: { end: end.toISOString() }, stations });
  await mkdir(fixtureDir, { recursive: true });
  const temporary = `${recording}.${process.pid}.tmp`;
  try {
    await writeFile(temporary, `${JSON.stringify(result)}\n`);
    await rename(temporary, recording);
  } finally { await rm(temporary, { force: true }); }
  return recording;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const command = process.argv[2];
  if (command === "prepare") console.log(await prepare());
  else if (command === "refresh") console.log(await refresh());
  else throw new Error("usage: node scripts/iwls-fixtures.mjs refresh|prepare");
}
