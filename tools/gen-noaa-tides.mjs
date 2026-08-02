/**
 * Generate Resources/stations.json — every bundled NOAA tide station.
 *
 * NOAA data is public domain and bundles; that is the whole reason the US side
 * of this app works with no signal and no account.
 *
 * PROVENANCE FILTER (M53). @neaps/tide-database is a WORLD database: 8,291
 * stations, of which 4,838 come from TICON-4/UHSLC under cc-by-4.0 and
 * cc-by-nc-4.0. Those terms are documented as "mixed, not fully spelled out"
 * (docs/research/market-research-2026-07-17.md §4), and the cc-by-nc set is
 * non-commercial outright. So the filter is BOTH halves of provenance, not
 * either:
 *
 *     license.type === "public domain"   AND   source.name === NOAA
 *
 * They select the same 3,452 stations today. Asserting both means a future
 * TICON row that arrives mislabelled `public domain` still cannot leak into a
 * shipped bundle — and the generator fails loudly if the two ever disagree.
 *
 * Three more filters, all inherited from slackwater-web's build-stations.mjs
 * and all still load-bearing:
 *
 *   - reference stations only. A subordinate is offsets against a reference
 *     and needs reduction math slackwater-engine has not ported; without it a
 *     subordinate is a dead pin on the map. (1,213 of the 3,452 are reference.)
 *   - at least one non-zero constituent, or there is nothing to predict.
 *   - zero-amplitude constituents dropped: they contribute nothing but bytes.
 *
 * And one that is new here: GEOGRAPHY, by upstream `country`, not a bbox.
 * "All of the US and Canada" is a statement about sovereignty, so it is read
 * off the field that states it. NOAA also publishes reference stations in
 * Mexico, Panama, Fiji, Bermuda and Indonesia — real data, outside the app's
 * stated coverage and outside the bundled basemap, so out.
 *
 * NAMING. Same enrichment path as the Salish bundle: names, contexts and
 * aliases come from @sailingnaturali/station-corrections so the iOS app, the
 * web app and the MCP fleet all say the same thing. The one addition is a
 * guard the Salish-sized bundle never needed — the resolver's fourth tier is
 * "nearest place from the bundled gazetteer", and that gazetteer holds 19
 * Salish Sea towns. Nationally it produces "San Francisco · near Olympia, WA".
 * So a DERIVED context is discarded and replaced with the station's own
 * state/province — the presentation NOAA itself uses ("Boston, MA").
 * ponytail: state code, not an expanded name. Expand it when the registry
 * grows a real national gazetteer, which is where curation belongs anyway.
 *
 * And one presentation fix the Salish bundle needed at two stations and the
 * national one needs at 201: NOAA writes a qualifier as the phrase that points
 * back at the name — "Discovery Island, 7.6 mi. SSE of". Split the name off and
 * the preposition dangles. Stripped at the data layer, once, rather than on
 * every render. Upstream symptom (station-corrections clean.js).
 * ponytail: strip the dangle here; delete when clean.js drops it upstream.
 *
 * Run: cd tools && npm install && node gen-noaa-tides.mjs
 */
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { allStations } from "@neaps/tide-database";
import { createBundledResolver } from "@sailingnaturali/station-corrections";

const NOAA = "US National Oceanic and Atmospheric Administration";
/** US (states + territories) and Canada — the app's stated coverage. */
export const COUNTRIES = new Set([
  "United States", "Puerto Rico", "Virgin Islands", "Guam",
  "Northern Mariana Islands", "American Samoa", "Canada",
]);

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "..", "Slackwater", "Resources", "stations.json");
const resolve = createBundledResolver();

/** "6.6 nm SSE of" -> "6.6 nm SSE". */
export const undangle = (s) => (s ?? "").replace(/\s+of$/i, "").trim();

const publicDomain = allStations.filter((s) => s.license?.type === "public domain");
const fromNoaa = allStations.filter((s) => s.source?.name === NOAA);
if (publicDomain.length !== fromNoaa.length ||
    publicDomain.some((s) => s.source?.name !== NOAA)) {
  throw new Error(
    "licence and source disagree about what is NOAA — inspect before shipping " +
    `(public domain: ${publicDomain.length}, NOAA: ${fromNoaa.length})`);
}

const stations = publicDomain
  .filter((s) => s.source?.name === NOAA)
  .filter((s) => COUNTRIES.has(s.country))
  .filter((s) => s.type === "reference")
  .filter((s) => s.harmonic_constituents?.some((c) => c.amplitude > 0))
  .map((s) => {
    const r = resolve({ id: s.id, name: s.name, latitude: s.latitude, longitude: s.longitude });
    return {
      id: s.id,
      name: r.name,
      // Fallback chain: state/province, then country — the unincorporated
      // Pacific islands (Midway, Wake, Johnston Atoll) carry no region at all.
      region: (r.derived ? "" : undangle(r.context)) ||
        ((s.country === "United States" || s.country === "Canada") && s.region) || s.country,
      aliases: r.aliases ?? [],
      latitude: s.latitude,
      longitude: s.longitude,
      timezone: s.timezone,
      chartDatum: s.chart_datum,
      // Heights come out relative to MSL; the datum shifts them to chart datum.
      datumOffset: s.datums?.MSL != null && s.datums?.[s.chart_datum] != null
        ? s.datums.MSL - s.datums[s.chart_datum]
        : 0,
      constituents: s.harmonic_constituents
        .filter((c) => c.amplitude > 0)
        .map((c) => ({ name: c.name, amplitude: c.amplitude, phase: c.phase })),
    };
  })
  // Codepoint compare with an id tiebreak, not localeCompare: the sort must be
  // the same on every machine that regenerates this file.
  .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));

if (stations.length < 1000) {
  throw new Error(`only ${stations.length} stations survived the filters — refusing to ship`);
}
if (stations.some((s) => !s.region)) {
  throw new Error("a station has no region line — every card needs its second line");
}

writeFileSync(out, JSON.stringify(stations));
const derived = stations.filter((s) => /^[A-Z]{2}$/.test(s.region)).length;
console.log(
  `${stations.length} NOAA public-domain reference tide stations, ` +
  `${(JSON.stringify(stations).length / 1024 / 1024).toFixed(2)} MB ` +
  `(${stations.length - derived} curated contexts, ${derived} state/province)`);
