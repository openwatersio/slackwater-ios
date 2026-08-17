/**
 * Generate Resources/stations.json — every bundled tide station.
 *
 * Bundled harmonic constants are the whole reason this app works with no
 * signal and no account, so the only question that decides what ships is
 * whether a station's licence lets it.
 *
 * LICENCE (M53, widened since). @neaps/tide-database is a WORLD database: at
 * 0.8.20260722, 8,291 stations, of which 4,838 come from TICON-4/UHSLC. The
 * generator used to gate on `license.type === "public domain" AND source.name
 * === NOAA`, a proxy for "can we ship this" written before the database
 * exposed the answer directly. It does now:
 *
 *     license.commercial_use === true
 *
 * That is one field, upstream-maintained, and it is the actual question. It
 * keeps NOAA's 3,452 public-domain rows AND TICON's 4,164 cc-by-4.0 rows,
 * excludes the 674 cc-by-nc-4.0 rows (GESLA upstream restricts commercial
 * use), and `=== true` drops the one malformed row whose `license` is a bare
 * string. A new public-domain source arriving upstream no longer needs an edit
 * here, and a source that loses its rights stops shipping without one.
 *
 * What this bought, honestly: about 200 more US saltwater stations, plus 49
 * Canadian gap-fills in water CHS does not gauge. It is NOT the whole cc-by
 * set — most of what that licence unlocks is either freshwater (see
 * FRESHWATER_NETWORKS in bundle.mjs) or a second, less accurate copy of a CHS
 * station (see CHS_COVERAGE_KM), and both are filtered out below. cc-by-4.0
 * obliges attribution, paid in SettingsView's "Data & attribution" section.
 *
 * Three more filters, all inherited from slackwater-web's build-stations.mjs
 * and all still load-bearing:
 *
 *   - reference stations only. A subordinate is offsets against a reference
 *     and needs reduction math slackwater-engine has not ported; without it a
 *     subordinate is a dead pin on the map.
 *   - at least one non-zero constituent, or there is nothing to predict.
 *   - zero-amplitude constituents dropped: they contribute nothing but bytes.
 *
 * GEOGRAPHY no longer gates anything — coverage was "all of the US and
 * Canada" behind a `country` allowlist (`COUNTRIES`); at world coverage
 * quality (licence, FRESHWATER_NETWORKS, the CHS cede rule, the datum check
 * below) decides what ships, and a station's country is no longer one of the
 * questions asked.
 *
 * `country` itself is trustworthy for NOAA rows and NOT for TICON's, which is
 * why COUNTRY_FIX exists below: upstream reads a station's operating agency as
 * its country, so the gauges NOAA runs abroad arrive claiming "United States".
 * With no COUNTRIES gate to drop them as a side effect, COUNTRY_FIX is what
 * lets them ship labelled honestly — Dakar as Senegal, not as a US station.
 * The other TICON-shaped correction, CA_PROVINCE, is documented at its
 * definition.
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
 * And two presentation fixes at the data layer, once, rather than on every
 * render — see undangle() and untrail(). NOAA writes a qualifier as the phrase
 * that points back at the name ("Discovery Island, 7.6 mi. SSE of"); TICON
 * repeats the state the region line already carries ("... Savannah Ga · GA").
 * ponytail: both are upstream symptoms; delete each when its source stops.
 *
 * Mixing two publishers also means DEDUPLICATION — they cover the same
 * harbours, and three pins on one anchorage is a worse map than one. See
 * DUPLICATE_KM.
 *
 * Run: cd tools && npm install && node gen-tides.mjs
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { allStations } from "@neaps/tide-database";
import {
  here, placesResolver, byNameThenId, undangle, REGION_WORD, writeBundle,
  FRESHWATER_NETWORKS, networkOf,
} from "./bundle.mjs";
import { km } from "./geo.mjs";
import { passesDatumCheck, DATUM_TOLERANCE_M } from "./datum-check.mjs";

const NOAA = "US National Oceanic and Atmospheric Administration";

/**
 * Upstream reads a station's OPERATING AGENCY as its country, so the 17 gauges
 * NOAA runs outside US waters arrive as "United States" — Dakar, Lagos, Suva,
 * Easter Island. Every one carries a `-usa-noaa` id suffix, which is the tell.
 *
 * Corrected, not deny-listed, because the correction is what is actually true
 * and it is the form the world bundle needs: these are keepers, they just have
 * to be labelled honestly — so worldwide they ship under the country this map
 * corrects them to, not as a seventh US territory.
 */
const COUNTRY_FIX = new Map([
  ["ticon/barbuda-9761115-usa-noaa", "Antigua and Barbuda"],
  ["ticon/bermuda-2695540-usa-noaa", "Bermuda"],
  ["ticon/bermuda_biological_station-2695535-usa-noaa", "Bermuda"],
  ["ticon/chuuk-1840000-usa-noaa", "Micronesia"],
  ["ticon/cochino_pequeno-9653601-usa-noaa", "Honduras"],
  ["ticon/dakar-7691360-usa-noaa", "Senegal"],
  ["ticon/diego_garcia-2431000-usa-noaa", "British Indian Ocean Territory"],
  ["ticon/diego_ramirez_island-9952000-usa-noaa", "Chile"],
  ["ticon/easter_island-9962420-usa-noaa", "Chile"],
  ["ticon/esperanza-1495000-usa-noaa", "Antarctica"],
  ["ticon/fare_ute_point-1732417-usa-noaa", "French Polynesia"],
  ["ticon/kwajalein-1820000-usa-noaa", "Marshall Islands"],
  ["ticon/lagos-7641400-usa-noaa", "Nigeria"],
  ["ticon/madero-9500966-usa-noaa", "Mexico"],
  ["ticon/settlement_point-9710441-usa-noaa", "Bahamas"],
  ["ticon/suva-1910000-usa-noaa", "Fiji"],
  ["ticon/valparaiso-9963950-usa-noaa", "Chile"],
]);

/**
 * Canadian rows carry GeoNames admin1 codes ("02"), not the province codes the
 * region line wants — a card reading "Alert Bay · 02" is worse than no line.
 * NOAA rows already carry "WA"/"ME", so this is TICON's shape, not Canada's.
 */
const CA_PROVINCE = {
  "01": "AB", "02": "BC", "03": "MB", "04": "NB", "05": "NL", "07": "NS",
  "08": "ON", "09": "PE", "10": "QC", "11": "SK", "12": "YT", "13": "NT",
  "14": "NU",
};

/**
 * NOAA and TICON both publish the same harbours: 670 TICON rows sit within a
 * kilometre of a NOAA gauge ("Aberdeen" / "ABERDEEN"), and 585 sit within a
 * kilometre of another TICON row ("Adak Alaska" twice, plus "Adak Island").
 * Three pins on one harbour is a worse map than one.
 *
 * 1 km, not 3: at 3 km this starts eating genuine neighbours — "Anacostia
 * River Aquatic Gardens" is 2.3 km from "Bladensburg, Md." and they are
 * different creeks with different curves. The residue is a handful of rounding
 * escapes (TICON positions are 2 dp, ~1 km), e.g. "Apra Harbor Guam" surviving
 * 1.34 km from "APRA HARBOR, GUAM".
 * ponytail: distance only. Add name similarity if the residue gets noticed.
 */
const DUPLICATE_KM = 1.0;

/**
 * CHS WINS IN CANADIAN WATER. TICON's Canadian rows overlap the CHS path
 * almost entirely — 195 of 262 sit within 3 km of a CHS station, and in BC it
 * is 84 of 88 — so bundling them wholesale would put two Victorias in the app.
 * Worse, they would be the less accurate Victoria: TICON computes datums
 * against the current epoch rather than an agency's adopted chart datum and
 * drifts 0.2-0.4 m on this coast (slackwater-web/scripts/build-stations.mjs
 * documents the same finding, and it is the per-station CHS LAT offset the
 * signalk-tides work turned up).
 *
 * So TICON fills GAPS in Canadian water and never competes: a Canadian station
 * ships only where CHS has nothing within CHS_COVERAGE_KM. The radius asks "is
 * this water already served", not "is this the same station" — hence 10 km
 * rather than the 3 km the registry uses for station identity.
 *
 * Read from the committed artefact, not regenerated: gen-chs-stations.mjs hits
 * the DFO API, and the tide bundle must not need a network to build.
 */
const CHS_COVERAGE_KM = 10;

const out = join(here, "..", "Slackwater", "Resources", "stations.json");
const chs = JSON.parse(
  readFileSync(join(here, "..", "Slackwater", "Resources", "chs-stations.json"), "utf8"));
const resolve = placesResolver();

/**
 * TICON repeats the state in the name, which the region line is already
 * showing: "Abercorn Creek near Savannah Ga · GA" says Georgia twice, on 571
 * cards, and "Brockville Ontario · ON" on 34 more. Both forms come off.
 *
 * Only a two-letter region is touched — those are the codes, so no regex
 * escaping and no risk of eating a place called "Santa Rita" — and the word
 * form only strips when it EXPANDS that same code, which is what keeps
 * "Kewaunee Lake Michigan · WI" intact.
 *
 * Several codes are tried, because the row's OWN code is not always the
 * province the card ends up showing. Upstream reads these Ontario gauges as
 * Michigan ("Tecumseh Ontario" and "La Salle Ontario" both arrive `region:
 * "MI"`, being across the river) or as a bare GeoNames number, so keying on it
 * alone looks for "Michigan", finds none, and ships the duplication the region
 * line then contradicts: "Tecumseh Ontario · ON".
 */
const untrail = (name, ...regions) => {
  for (const region of regions) {
    if (!/^[A-Z]{2}$/.test(region ?? "")) continue;
    const word = REGION_WORD[region];
    const trimmed = name
      .replace(new RegExp(`\\s+(${region}${word ? `|${word}` : ""})$`, "i"), "")
      .trim();
    if (trimmed) name = trimmed;
  }
  return name;
};

/** The state/province code a region line ends in — "~LaSalle, ON" -> "ON". */
const trailingCode = (region) => region.match(/\b([A-Z]{2})$/)?.[1];

const countryOf = (s) => COUNTRY_FIX.get(s.id) ?? s.country;
const regionOf = (s) => {
  const r = (countryOf(s) === "Canada" && CA_PROVINCE[s.region]) || s.region;
  // A GeoNames code that survived the map is a cross-border mislabel — five
  // Great Lakes gauges carry Ontario's "08" on the US shore. "Algonac · 08"
  // is worse than "Algonac · United States", so let it fall through.
  return /^[0-9]+$/.test(r ?? "") ? "" : r;
};

/**
 * LICENCE. The database is a world database and mixes three licences; the one
 * that matters is TICON's cc-by-nc-4.0 set (674 stations, GESLA upstream),
 * which forbids commercial use and so can never ship.
 *
 * The gate is upstream's own machine-readable answer, `license.commercial_use`
 * — not an allowlist of publishers. It is the field that states the thing we
 * need to know, it covers licences nobody has added yet, and `=== true` drops
 * the one malformed row (`baltic-sea.geo`, whose `license` is a string) for
 * free. cc-by-4.0 obliges ATTRIBUTION, which the app pays in its credits
 * screen — see ATTRIBUTION below.
 */
const shippable = allStations.filter((s) => s.license?.commercial_use === true);

/**
 * One pin per place. NOAA wins ties outright: public domain, curated names,
 * finer positions, and the ids that already-stored fits and favourites are
 * keyed on. Beyond that, lowest id wins, so the survivor of a TICON/TICON pair
 * is the same on every machine that regenerates this file.
 */
const grid = new Map();
const cell = (la, lo) => `${Math.round(la * 20)}:${Math.round(lo * 20)}`;
// +-2 cells of 0.05deg: >= 1.4 km of longitude even at Alert (82.5N), so the
// search window always contains everything within DUPLICATE_KM.
const collides = (s) => {
  for (let i = -2; i <= 2; i++) {
    for (let j = -2; j <= 2; j++) {
      for (const k of grid.get(cell(s.latitude + i / 20, s.longitude + j / 20)) ?? []) {
        if (km(s, k) < DUPLICATE_KM) return true;
      }
    }
  }
  return false;
};
/** Only kept stations go in, and a kept station ALWAYS goes in — a NOAA row
 *  that survives a collision still has to block the TICON row behind it. */
const remember = (s) => {
  const k = cell(s.latitude, s.longitude);
  grid.set(k, [...(grid.get(k) ?? []), s]);
};

/**
 * Canadian water CHS already serves — see CHS_COVERAGE_KM. TICON rows only:
 * the reason to cede is that TICON's datums are not the adopted ones, which
 * says nothing about NOAA's, and NOAA has stations in Canadian water that were
 * already shipping (Hyder, on the Portland Canal, which upstream files under
 * Canada and CHS gauges 1.3 km away at Stewart).
 */
let cededToChs = 0;
const servedByChs = (s) =>
  s.source?.name !== NOAA &&
  countryOf(s) === "Canada" &&
  chs.some((c) => km(s, c) <= CHS_COVERAGE_KM);

let dropped = 0;
let failedDatum = 0;
const stations = shippable
  .filter((s) => !FRESHWATER_NETWORKS.has(networkOf(s)))
  .filter((s) => (servedByChs(s) ? (cededToChs++, false) : true))
  .filter((s) => s.type === "reference")
  .filter((s) => s.harmonic_constituents?.some((c) => c.amplitude > 0))
  .filter((s) => (passesDatumCheck(s) ? true : (failedDatum++, false)))
  .sort((a, b) =>
    (a.source?.name === NOAA ? 0 : 1) - (b.source?.name === NOAA ? 0 : 1) ||
    (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  // A NOAA row is never dropped. It was already shipping, users have fits and
  // favourites keyed on its id, and NOAA publishing two gauges a few hundred
  // metres apart ("Garden City Pier (ocean)") is a judgement it is entitled to
  // make. Deduplication is about what TICON ADDS, so only TICON rows yield.
  .filter((s) => {
    if (collides(s) && s.source?.name !== NOAA) { dropped++; return false; }
    remember(s);
    return true;
  })
  .map((s) => {
    const r = resolve({ id: s.id, name: s.name, latitude: s.latitude, longitude: s.longitude });
    // The state/province code. Not always the region line any more — a derived
    // context outranks it — but still its own fact, and `untrail` needs it
    // whatever gets displayed (see below).
    const code = ((countryOf(s) === "United States" || countryOf(s) === "Canada") && regionOf(s)) || "";
    // Fallback chain: curated or derived context, then state/province, then
    // country — the unincorporated Pacific islands (Midway, Wake, Johnston
    // Atoll) carry no region at all.
    //
    // A DERIVED context is no longer discarded. It used to be, because the
    // gazetteer behind it held 19 Salish towns and nationally produced "San
    // Francisco · near Olympia, WA"; station-corrections 2.8.0 derives from a
    // national places list instead, capped at 40 km, so "~Bellingham, WA" beats
    // the bare "WA" it replaces — it says the same thing and more.
    const region = undangle(r.context) || code || countryOf(s);
    return {
      id: s.id,
      // Trailing-state cleanup keys on the CODE, not the region line. Those
      // parted company when a derived context started winning: "Abercorn Creek
      // near Savannah Ga" reads beside "~Savannah, GA", and passing the label
      // here would stop stripping the "Ga" on 571 cards.
      name: untrail(r.name, code, trailingCode(region)),
      region,
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
  .sort(byNameThenId);

// Measured 2026-08-17 at world coverage: 2,895. The plan's ~3,800 estimate was
// taken before dedup ran at world scale and undercounted it — DUPLICATE_KM
// (1 km, unchanged by this task) now also collapses UHSLC's own redundant
// fast-delivery/research-quality feeds (435 stations, most of them nowhere
// near North America) and Mexico's multi-sensor-per-pier UNAM rows (46), on
// top of the TICON-mirrors-NOAA duplication (458) that already dominated the
// old 1,300-floor North America bundle. 2,500 keeps the floor a sanity check
// against a broken filter, not a tautology of today's exact count.
if (stations.length < 2500) {
  throw new Error(`only ${stations.length} stations survived the filters — refusing to ship`);
}
if (stations.some((s) => !s.region)) {
  throw new Error("a station has no region line — every card needs its second line");
}
// The licence gate is the one filter whose failure is a legal problem rather
// than a quality one, so it is asserted on the way OUT as well as applied on
// the way in — a future refactor of the pipeline above cannot quietly lose it.
const ids = new Set(stations.map((s) => s.id));
if (allStations.some((s) => ids.has(s.id) && s.license?.commercial_use !== true)) {
  throw new Error("a station without commercial-use rights reached the bundle");
}
// TICON must never compete with CHS in the water CHS serves. If a Victoria or
// a Point Atkinson shows up here, servedByChs has stopped working and the app
// is about to show two of them.
// Canadian by the SOURCE's country, not by the region line reading like a
// province code. The line stopped being a reliable carrier of that the moment
// a derived context could win it ("~Sidney, BC"), and this guard failing open
// is how two Victorias reach the map — so it reads the fact, not the label.
const canadianIds = new Set(allStations.filter((s) => countryOf(s) === "Canada").map((s) => s.id));
const canadian = stations.filter((s) => canadianIds.has(s.id));
const contested = canadian.filter((s) =>
  s.id.startsWith("ticon/") && chs.some((c) => km(s, c) <= CHS_COVERAGE_KM));
if (contested.length) {
  throw new Error(
    `${contested.length} Canadian stations duplicate a CHS station: ` +
    contested.slice(0, 5).map((s) => s.name).join(", "));
}

const size = writeBundle(out, stations);
const towns = stations.filter((s) => s.region.startsWith("~")).length;
const codes = stations.filter((s) => /^[A-Z]{2}$/.test(s.region)).length;
console.log(
  `${stations.length} reference tide stations, ${size} ` +
  `(${stations.length - towns - codes} curated contexts, ${towns} nearest town, ` +
  `${codes} state/province; ` +
  `${canadian.length} Canadian gap-fills, ${cededToChs} ceded to CHS; ` +
  `${dropped} duplicates dropped; ${failedDatum} failed the ${DATUM_TOLERANCE_M} m datum check)`);
