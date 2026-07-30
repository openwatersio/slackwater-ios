// Fetch IWLS wlp (fit + validation) and wlp-hilo (validation extremes) for
// Victoria Harbour, 7-day chunks, cached on disk, 2.5 s between live requests.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const cacheDir = join(here, "cache");
mkdirSync(cacheDir, { recursive: true });

const STATION = "5cebf1df3d0f4a073c4bbd1e"; // Victoria Harbour 07120
const BASE = "https://api-sine.dfo-mpo.gc.ca/api/v1";
const UA = "chs-fit-spike/0.1";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getChunk(series, fromIso, toIso) {
  const key = `${series}_${fromIso.slice(0, 10)}_${toIso.slice(0, 10)}.json`;
  const path = join(cacheDir, key);
  if (existsSync(path)) return JSON.parse(readFileSync(path, "utf8"));
  const url = `${BASE}/stations/${STATION}/data?time-series-code=${series}&from=${fromIso}&to=${toIso}`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  const data = await res.json();
  writeFileSync(path, JSON.stringify(data));
  await sleep(2500);
  return data;
}

async function fetchRange(series, start, end) {
  const out = [];
  for (let t = new Date(start); t < end; ) {
    const next = new Date(Math.min(t.getTime() + 7 * 86400_000, end.getTime()));
    const chunk = await getChunk(series, t.toISOString().replace(/\.\d+Z/, "Z"), next.toISOString().replace(/\.\d+Z/, "Z"));
    out.push(...chunk);
    t = next;
  }
  // de-dup on eventDate (chunk boundaries can repeat a point)
  const seen = new Set();
  return out.filter((p) => !seen.has(p.eventDate) && seen.add(p.eventDate));
}

const FIT_START = new Date("2026-05-25T00:00:00Z");
const FIT_END = new Date("2026-07-24T00:00:00Z"); // 60 days
const VAL_START = new Date("2026-08-21T00:00:00Z");
const VAL_END = new Date("2026-08-28T00:00:00Z"); // 7 days, 4 weeks after fit end

const fit = await fetchRange("wlp", FIT_START, FIT_END);
const val = await fetchRange("wlp", VAL_START, VAL_END);
const hilo = await fetchRange("wlp-hilo", VAL_START, VAL_END);

const compact = (arr) => arr.map((p) => ({ t: new Date(p.eventDate).getTime(), v: p.value }));
const quarterHourly = (arr) => compact(arr).filter((p) => p.t % 900_000 === 0); // wlp is 1-min; 15-min is plenty
writeFileSync(join(here, "fit-window.json"), JSON.stringify(quarterHourly(fit)));
writeFileSync(join(here, "validation-window.json"), JSON.stringify(quarterHourly(val)));
writeFileSync(join(here, "validation-hilo.json"), JSON.stringify(compact(hilo)));
console.log(`fit: ${fit.length} pts (${fit[0]?.eventDate} .. ${fit.at(-1)?.eventDate})`);
console.log(`val: ${val.length} pts, hilo: ${hilo.length} events`);
console.log("hilo sample:", JSON.stringify(hilo.slice(0, 3)));
