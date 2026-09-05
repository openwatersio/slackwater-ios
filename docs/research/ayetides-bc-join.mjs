// Join AyeTides' British Columbia stations against the OSM coastline and CHS's own
// positions, split by whether the coordinate sits on a whole arc-minute.
//
//   node ayetides-bc-join.mjs path/to/stations.js
//
// Needs a sibling checkout of openwaters/station-metadata (coastline + haversine).
// Rivers and inlet heads count as land in the OSM land polygons, so "on land" is
// inflated for Fraser-delta and estuary stations in both groups; the CHS
// displacement column does not have that problem. See
// ayetides-station-database-2026-09-04.md.
import { readFileSync } from 'node:fs';
import * as coast from '../../../station-metadata/src/coastline.js';
import { haversineMetres } from '../../../station-metadata/src/positions.js';

const S = process.argv[2].replace(/[^/]*$/, '');
const raw = readFileSync(process.argv[2], 'utf8');
const rows = [...raw.matchAll(/\[\s*(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]/g)]
  .map(m => ({ lat: +m[1], lon: +m[2], name: m[3] }));
const resid = v => Math.abs(Math.abs(v) * 60 - Math.round(Math.abs(v) * 60));
const bc = rows.filter(r => r.name.replace(/\s*Current$/, '').endsWith(', British Columbia'))
  .map(r => ({ ...r, whole: Math.max(resid(r.lat), resid(r.lon)) < 0.004, current: /Current$/.test(r.name) }));

const chs = JSON.parse(readFileSync(new URL('../../Slackwater/Resources/chs-stations.json', import.meta.url), 'utf8'))
  .filter(s => /, BC$/.test(s.region || ''));
const norm = s => s.toLowerCase().replace(/\(.*?\)/g, '').replace(/\b(harbour|harbor|hbr)\b/g, 'harbour').replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
const chsByName = new Map(chs.map(s => [norm(s.name), s]));

const inland = coast.inlandMetres ? (lat, lon) => coast.inlandMetres(lat, lon) : null;
const covered = coast.isCovered || coast.inCoverage || (() => true);

let out = [];
for (const r of bc) {
  const base = r.name.replace(/\s*Current$/, '').replace(/, British Columbia$/, '');
  const short = base.split(',')[0];
  const match = chsByName.get(norm(short)) || chsByName.get(norm(base));
  const onLand = coast.isOnLand(r.lat, r.lon);
  const m = inland && onLand ? inland(r.lat, r.lon) : (onLand ? null : 0);
  out.push({ ...r, base, onLand, inlandM: m, chs: match ? haversineMetres({ latitude: r.lat, longitude: r.lon }, match) : null, chsName: match?.name, cov: covered(r.lat, r.lon) });
}
const g = (pred) => out.filter(pred);
const pct = (a, b) => `${a.length}/${b.length} (${(100 * a.length / b.length).toFixed(0)}%)`;
const median = xs => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : NaN; };
for (const [label, set] of [['whole-minute', out.filter(o => o.whole)], ['precise', out.filter(o => !o.whole)]]) {
  const land = set.filter(o => o.onLand);
  const far = set.filter(o => o.onLand && o.inlandM !== null && o.inlandM > 200);
  const matched = set.filter(o => o.chs !== null);
  console.log(`${label}: n=${set.length}  on land ${pct(land, set)}  >200 m inland ${pct(far, set)}  matched to CHS ${matched.length}, median displacement ${Math.round(median(matched.map(o => o.chs)))} m, >500 m ${pct(matched.filter(o => o.chs > 500), matched)}`);
}
console.log('coverage: uncovered', out.filter(o => !o.cov).length, 'of', out.length, '| current stations', out.filter(o=>o.current).length);
console.log('\nworst whole-minute on-land examples:');
for (const o of out.filter(o => o.whole && o.onLand).sort((a, b) => (b.inlandM ?? 0) - (a.inlandM ?? 0)).slice(0, 8))
  console.log(`  ${o.base}${o.current?' (current)':''}: ${o.lat},${o.lon} inland ${Math.round(o.inlandM ?? -1)} m${o.chs!==null?`, CHS "${o.chsName}" ${Math.round(o.chs)} m away`:''}`);
console.log('\nprecise on-land examples:');
for (const o of out.filter(o => !o.whole && o.onLand).sort((a, b) => (b.inlandM ?? 0) - (a.inlandM ?? 0)).slice(0, 5))
  console.log(`  ${o.base}${o.current?' (current)':''}: ${o.lat},${o.lon} inland ${Math.round(o.inlandM ?? -1)} m${o.chs!==null?`, CHS "${o.chsName}" ${Math.round(o.chs)} m away`:''}`);
