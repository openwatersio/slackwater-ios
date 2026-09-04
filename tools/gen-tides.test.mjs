/**
 * Invariants for the generated Resources/stations.json.
 *
 * These assert on the ARTEFACT, not on the generator's internals, because the
 * artefact is what ships and it is the only thing an Xcode build reads. Run
 * after the generator: `npm test`.
 *
 * node:test and node:assert are stdlib — this deliberately adds no dependency.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { allStations } from "@neaps/tide-database";
import {
  here, REGION_WORD, FRESHWATER_NETWORKS, networkOf, NORTH_AMERICA, SAME_PLACE_KM,
  placesResolver, undangle,
} from "./bundle.mjs";
import { km } from "./geo.mjs";
import { passesDatumCheck } from "./datum-check.mjs";

const stations = JSON.parse(
  readFileSync(join(here, "..", "Slackwater", "Resources", "stations.json"), "utf8"));

// The one failure that is a legal problem rather than a quality one, checked
// independently of the generator that is supposed to prevent it.
test("no station without commercial-use rights ships", () => {
  const rights = new Map(allStations.map((s) => [s.id, s.license?.commercial_use]));
  const bad = stations.filter((s) => rights.get(s.id) !== true);
  assert.deepEqual(bad.map((s) => s.id), []);
});

// TICON rows yield to anything already kept; NOAA-vs-NOAA pairs are NOAA's
// call and were shipping before this filter existed.
test("no TICON station sits within the dedupe radius of another station", () => {
  const grid = new Map();
  const cell = (la, lo) => `${Math.round(la * 20)}:${Math.round(lo * 20)}`;
  const collisions = [];
  for (const s of stations) {
    for (let i = -2; i <= 2; i++) {
      for (let j = -2; j <= 2; j++) {
        for (const k of grid.get(cell(s.latitude + i / 20, s.longitude + j / 20)) ?? []) {
          if (km(s, k) < 1.0 && (s.id.startsWith("ticon/") || k.id.startsWith("ticon/"))) {
            collisions.push(`${s.name} / ${k.name}`);
          }
        }
      }
    }
    const k = cell(s.latitude, s.longitude);
    grid.set(k, [...(grid.get(k) ?? []), s]);
  }
  assert.deepEqual(collisions, []);
});

// untrail(): TICON repeats the state the region line already shows, as the
// code ("... Savannah Ga · GA") and as the word ("Brockville Ontario · ON") —
// and, at world coverage, as a bare country name ("Praia Cape Verde · Cape
// Verde", "Syowa Antarctica · Antarctica" ×2). Task 4 extended untrail() to
// strip any region word, not just a two-letter code.
test("no name ends in its own region", () => {
  const doubled = stations
    .filter((s) => new RegExp(
      `\\s(${s.region}${REGION_WORD[s.region] ? `|${REGION_WORD[s.region]}` : ""})$`, "i").test(s.name))
    .map((s) => `${s.name} · ${s.region}`);
  assert.deepEqual(doubled, []);
});

// Task 4 (region lines for the world). The gazetteer behind the derived
// context tier is 9,660 US, Canadian and territory towns; outside those
// countries it must never be trusted — nationally it produced "San Francisco
// · near Olympia, WA", and Matamoros, MX sits 2.8 km from Brownsville, TX,
// inside the resolver's own 40 km derivation radius. Nothing this close
// currently reaches the naming stage (Matamoros ships as a `subordinate` row
// and is filtered out earlier), which is why this asserts on the bundle
// rather than reproducing a live failure — it is the guard against a future
// upstream row landing where Matamoros almost does.
test("no station outside North America carries a gazetteer-derived region", () => {
  // stations.json carries no `country` field — correlate back to the
  // upstream row by id, same as the licence and "reaches beyond North
  // America" tests above.
  const byId = new Map(allStations.map((s) => [s.id, s]));
  // station-metadata 5.0.0 dropped the "~" a derived context used to carry,
  // so a derived label can no longer be spotted by its glyph. Ask the same
  // resolver gen-tides.mjs uses: a station outside North America whose
  // shipped region is a context the resolver marked `derived` got past the
  // gate. Non-derived contexts ("Djakarta, Java" -> "Java") are upstream's
  // own words and are allowed anywhere.
  const resolve = placesResolver();
  const borrowed = stations
    .filter((s) => {
      const raw = byId.get(s.id);
      const c = raw?.country;
      if (!c || NORTH_AMERICA.has(c)) return false;
      const r = resolve({ id: raw.id, name: raw.name, latitude: raw.latitude, longitude: raw.longitude });
      return r.derived && s.region === undangle(r.context);
    })
    .map((s) => `${s.name} · ${s.region}`);
  assert.deepEqual(borrowed, []);
});

test("every station has a region line and a usable model", () => {
  for (const s of stations) {
    assert.ok(s.region, `${s.name} has no region`);
    if (s.reference) {  // a subordinate's model is its offsets (see below)
      assert.ok(s.offsets?.time && s.offsets?.height, `${s.name} has no offsets`);
      continue;
    }
    assert.ok(s.constituents.length > 0, `${s.name} has no constituents`);
    assert.ok(s.constituents.every((c) => c.amplitude > 0), `${s.name} has a dead constituent`);
  }
});

// TICON fills gaps in Canadian water; it must never compete with CHS, whose
// datums are the adopted ones. Two Victorias is the failure this catches.
test("no bundled Canadian station duplicates a CHS station", () => {
  const chs = JSON.parse(readFileSync(
    join(here, "..", "Slackwater", "Resources", "chs-stations.json"), "utf8"));
  // The province code either IS the region line or ends it — "BC" and
  // "Sidney, BC" are both Canadian. Matching only the bare code quietly
  // shrank this check to 25 stations the day nearest-town labels landed, which
  // is the wrong way for a duplicate-detector to fail. Read from the shipped
  // file rather than the generator's own bookkeeping, deliberately: that is
  // what makes this an independent check and not a restatement.
  const ca = stations.filter((s) =>
    /(^|,\s)(AB|BC|MB|NB|NL|NS|ON|PE|QC|SK|YT|NT|NU)$/.test(s.region));
  // NOAA rows are exempt: their datums are adopted, and Hyder was already
  // shipping when CHS gauges Stewart 1.3 km away.
  const contested = ca
    .filter((s) => s.id.startsWith("ticon/") && chs.some((c) => km(s, c) <= 10))
    .map((s) => s.name);
  assert.deepEqual(contested, []);
  assert.ok(ca.length > 30, `only ${ca.length} Canadian gap-fills`);
});

// COUNTRY_FIX: upstream reads NOAA's operating agency as the country, so the
// gauges NOAA runs abroad arrive claiming "United States". Before Task 3 this
// test asserted the five below did not ship at all — true only as a side
// effect of the COUNTRIES sovereignty allowlist, which dropped them because
// their corrected country wasn't US/Canada. Worldwide they are keepers (see
// COUNTRY_FIX's own comment in gen-tides.mjs), so the assertion worth keeping
// is the one the test's name always claimed: they don't ship AS US.
test("stations NOAA runs abroad do not ship as US", () => {
  const abroad = stations.filter((s) =>
    ["Dakar", "Lagos", "Suva", "Easter Island", "Diego Garcia"].includes(s.name));
  assert.ok(abroad.length > 0, "none of the NOAA-abroad stations shipped");
  const asUS = abroad.filter((s) => /^[A-Z]{2}$/.test(s.region) || s.region === "United States");
  assert.deepEqual(asUS.map((s) => s.name), []);
});

// Task 1 (world coverage): a precondition guard for the datum-validation
// gate Task 2 adds to gen-tides.mjs, which will read MHW/MLW off the
// upstream row. Both 0.8.20260722 and 0.9.20260801 already publish these on
// every commercial-ok TICON row (verified directly against allStations on
// each version — 4,164/4,164, zero blind), so this test is green today. It
// exists so that if a future upstream release drops the fields, this fails
// loudly here instead of Task 2's gate silently passing everything.
test("every TICON row carries the datums the quality gate reads", () => {
  const ticon = allStations.filter(
    (s) => s.id.startsWith("ticon/") && s.license?.commercial_use === true);
  assert.ok(ticon.length > 4000, `only ${ticon.length} commercial-ok TICON rows`);
  const blind = ticon.filter(
    (s) => s.datums?.MHW === undefined || s.datums?.MLW === undefined);
  assert.deepEqual(blind.map((s) => s.id), []);
});

// Task 3 (world coverage). The two gates that confined the app to North
// America were an allowlist of seven sovereignty strings and an allowlist of
// eight operator codes — neither about licence, and the second written only to
// keep US river gauges out.
test("the bundle reaches beyond North America", () => {
  // stations.json carries no `country` field (see the map() in gen-tides.mjs)
  // — correlate back to the upstream row by id, same as the licence test above.
  const country = new Map(allStations.map((s) => [s.id, s.country]));
  const countries = new Set(stations.map((s) => country.get(s.id)));
  for (const expected of ["United Kingdom", "France", "Germany", "Netherlands"]) {
    assert.ok(countries.has(expected), `${expected} is missing from the bundle`);
  }
});

// Bryan opened the app in the Solent and Near Me ranked stations 4,700 nm
// away. These three are the acceptance test for that. Southampton is
// deliberately not in `want`: it fails the datum gate at 0.53 m (see the
// next test) and must not ship — asserting it present here would contradict
// the entire point of the gate.
test("the Solent is in the bundle", () => {
  const want = ["Portsmouth", "Lymington", "Bournemouth"];
  const solent = stations.filter(
    (s) => want.includes(s.name) && s.latitude > 50 && s.latitude < 51
           && s.longitude > -2.5 && s.longitude < -0.5);
  assert.deepEqual(solent.map((s) => s.name).sort(), want.sort());
});

// Freshwater instrumentation is still the thing being excluded — 328 Louisiana
// marsh platforms named after the nearest town is nine "Abbeville · LA" rows on
// nine bayou platforms nobody can moor at.
test("no freshwater-network station ships", () => {
  const network = new Map(allStations.map((s) => [s.id, networkOf(s)]));
  const fresh = stations.filter((s) => FRESHWATER_NETWORKS.has(network.get(s.id)));
  assert.deepEqual(fresh.map((s) => s.id), []);
});

// Four UK publishers cover the same harbours — bodc, cco, noc and da_idh, plus
// two UHSLC feeds. The 1 km rule collapses co-located gauges; two gauges on one
// harbour a few km apart survive it and put three pins on one anchorage.
//
// NOAA-vs-NOAA pairs are exempt, same as the DUPLICATE_KM test above and for
// the same reason: NOAA already publishes distinct nearby gauges under names
// that collapse to the same word once trimmed to a card ("Philadelphia, US
// Coast Guard Station" and "Philadelphia, Municipal Pier 11" both ship as
// "Philadelphia", 2.3 km apart) — that pairing predates this task and is
// NOAA's call, not a multi-publisher duplicate to collapse.
test("no two bundled stations share a name within sight of each other", () => {
  const byName = new Map();
  for (const s of stations) {
    const key = s.name.toLowerCase();
    byName.set(key, [...(byName.get(key) ?? []), s]);
  }
  const collisions = [];
  for (const [, group] of byName) {
    for (let i = 0; i < group.length; i++) {
      for (let j = i + 1; j < group.length; j++) {
        if (km(group[i], group[j]) < SAME_PLACE_KM &&
            (group[i].id.startsWith("ticon/") || group[j].id.startsWith("ticon/"))) {
          collisions.push(`${group[i].name} (${group[i].id} / ${group[j].id})`);
        }
      }
    }
  }
  assert.deepEqual(collisions, []);
});

// A NOAA row that FAILS the datum gate must still block the TICON refit of the
// same gauge. The gate ran as a filter before the dedupe, so a failing NOAA row
// left the pipeline and stopped blocking: Anchorage's `noaa/9455920` (120
// constituents, 0.308) was rejected and `ticon/anchorage-9455920-usa-noaa` (50
// constituents, scored 0.237 against TICON's OWN recomputed datums) shipped in
// its place from the identical position — the gate PROMOTING the model it had
// just rejected, in Upper Cook Inlet, where a linear harmonic model is at its
// worst. "We cannot vouch for this water" has to yield no station.
//
// Proven red: run against the bundle generated before the fix and Anchorage
// appears here at 0.0 km.
test("nothing ships in the water a gate-failing NOAA row was rejected for", () => {
  const bundled = new Set(stations.map((s) => s.id));
  const rejectedNoaa = allStations.filter(
    (s) => s.license?.commercial_use === true
        && s.source?.name === "US National Oceanic and Atmospheric Administration"
        && !passesDatumCheck(s));
  assert.ok(rejectedNoaa.length > 0, "no NOAA row fails the gate — this test is vacuous");
  const promoted = [];
  for (const r of rejectedNoaa) {
    if (bundled.has(r.id)) promoted.push(`${r.name} shipped despite failing`);
    for (const s of stations) {
      if (km(r, s) < 1.0) promoted.push(`${s.name} (${s.id}) replaced ${r.id}`);
    }
  }
  assert.deepEqual(promoted, []);
});

// UHSLC's two feeds of one gauge disagree on POSITION by more than
// SAME_PLACE_KM (Port Stanley by 105.7 km, into open South Atlantic water) and
// sometimes on NAME ("Male" / "Male Hulule"), so neither the radius rule nor
// the name-gated one collapses them. The station number in the id does.
test("no UHSLC gauge ships through both of its feeds", () => {
  const key = (id) =>
    id.match(/-(\d+)[a-z]?-([a-z]{3})-uhslc_(?:fd|rq)$/)?.slice(1, 3).join("-");
  const seen = new Map();
  const dupes = [];
  for (const s of stations) {
    const k = key(s.id);
    if (k === undefined) continue;
    if (seen.has(k)) dupes.push(`${k}: ${seen.get(k).id} / ${s.id}`);
    else seen.set(k, s);
  }
  assert.ok(seen.size > 300, `only ${seen.size} UHSLC gauges — the id shape changed`);
  assert.deepEqual(dupes, []);
});

// The gate is only worth having if it actually removed something. Southampton
// is a double high water port whose model disagrees with its own published
// datums by 0.53 m; it must not be in the bundle at any range.
test("stations that fail the datum gate are not bundled", () => {
  const bundled = new Set(stations.map((s) => s.id));
  // Subordinates never run the gate: their constituents are the reference's copy.
  const rejected = allStations.filter(
    (s) => s.license?.commercial_use === true && s.type !== "subordinate"
        && !passesDatumCheck(s) && bundled.has(s.id));
  assert.deepEqual(rejected.map((s) => s.id), []);
  const soton = allStations.find(
    (s) => s.name === "Southampton" && s.country === "United Kingdom");
  assert.ok(!bundled.has(soton.id), "Southampton failed the gate but shipped anyway");
});

// Subordinate stations (#229). A subordinate has no model of its own: its
// predictions are its reference's highs and lows, shifted and scaled by the
// `offsets` block. Upstream copies the reference's constituents onto every
// subordinate row verbatim, so shipping them would predict the reference's
// water under the subordinate's name — they must be dropped, and the
// reference must be on the device or the station is a dead pin.
const subordinates = stations.filter((s) => s.reference);

test("Nurse Channel ships as a subordinate of a bundled reference", () => {
  const nurse = stations.find((s) => s.id === "noaa/TEC4635");
  assert.ok(nurse, "noaa/TEC4635 is not in the bundle");
  assert.equal(nurse.reference, "noaa/9710441");
  assert.deepEqual(nurse.offsets, {
    time: { high: 0, low: 10 },
    height: { type: "ratio", high: 0.79, low: 1.11 },
  });
});

test("every subordinate's reference ships in the bundle", () => {
  const ids = new Set(stations.map((s) => s.id));
  assert.ok(subordinates.length > 2000, `only ${subordinates.length} subordinates`);
  assert.deepEqual(subordinates.filter((s) => !ids.has(s.reference)).map((s) => s.id), []);
});

test("no subordinate carries constituents", () => {
  assert.deepEqual(subordinates.filter((s) => s.constituents?.length).map((s) => s.id), []);
});
