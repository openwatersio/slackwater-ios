# Global coverage — the world floor, region packs, and the UK

**Status:** design, approved 2026-08-16. **Partly delivered — read this header before
citing anything below as shipped.**
**Scope:** tide stations and basemap, worldwide. Currents are researched separately and
explicitly out of this spec.

> **What the `feat/global-coverage` branch actually delivered:** §1 (the station gates),
> §3 (validation — see `docs/validation/world-tide-stations.md`) and §5. The station
> allowlists are gone and 2,765 stations ship worldwide behind a measured datum gate.
>
> **§2 (the world basemap floor, its three tiers and its Delivery subsection) and success
> criteria 2, 3 and 4 are Plan B and were NOT built.** The map still ships the national
> basemap. Do not read §2 as a description of the app.
>
> **Criterion 1 names two stations that do not exist.** `@neaps/tide-database` has zero
> rows for Cowes and zero for Poole, at any licence — so no gate could have shipped them
> and no future one will without an upstream row. The Solent acceptance test
> (`tools/gen-tides.test.mjs`, "the Solent is in the bundle") asserts the three that do
> exist: **Portsmouth, Lymington and Bournemouth**. Southampton exists and is
> deliberately excluded — it fails the datum gate at 0.529 m. §3's use of Poole as an
> example double-tide port is subject to the same correction.

## Why now

Bryan opened Slackwater in the UK and it did nothing: Near Me ranked stations 4,700 nm
away and the map drew blank tiles. Both failures are build-time gates, not engine
limits — `slackwater-engine` is 970 lines of harmonic math with no geography in it.

`planning/commitments.md` line 29 (due 2026-09-01) already framed the work:

> World coverage is no longer blocked on licensing — it is blocked on the BASEMAP:
> `land-usca.pmtiles` is continental at z0-9, so most of the ~5,372 cc-by world stations
> would drop pins on blank tiles. Drop the `COUNTRIES` gate only after the map story exists.

**Measurement inverts that premise.** The basemap was never the blocker; the *national*
basemap was. A worldwide floor costs less than the US+Canada tier we ship today.

## 1. What is actually gated

Two allowlists in `tools/gen-tides.mjs`, both hardcoded:

- `COUNTRIES` (line 78) — seven sovereignty strings, US territories and Canada.
- `NETWORKS` (line 163) — eight operator codes, written to exclude US freshwater
  instrumentation (`crms`, `usgs`, `cdwr`), not to exclude other countries.

The UK's 89 shippable stations sit on six networks. **Twenty-two of them
(`uhslc_fd` 8, `uhslc_rq` 14) already pass `NETWORKS`** and are blocked by `COUNTRIES`
alone. The other 67 need `bodc` (41), `cco` (16), `noc` (5), `da_idh` (5) added.

Nothing about licence blocks any of this. `@neaps/tide-database` is a world database —
8,291 stations, 7,616 passing the shipping `license.commercial_use === true` gate:

| | commercial-ok |
|---|---|
| United Kingdom | 89 |
| Ireland | 38 |
| France | 147 |
| Netherlands | 179 |
| Germany | 149 |
| **Europe total** | **833** |

All reference stations, ~50 constituents each, `chart_datum: "LAT"` — the UK convention,
so no datum translation is needed — and zero missing a `datums` block. `timezone` is
populated (`Europe/London`) and the app already reads it per-station.

Budget at the documented ~3 KB/station: the whole world is about 23 MB of JSON against
today's 2.5 MB. **Station data is not the constraint. It never was.**

## 2. The map: three tiers, and the app gets smaller

Cut against the live archives on 2026-08-16 (`pmtiles extract`, `-11,49.5,3,61` for the UK,
`-180,-85,180,85` for the world, same layer strip `build-seamap.sh` applies):

| Layer | Today (US+CA) | World floor | UK pack |
|---|---|---|---|
| seamap (stripped) | z0-9 · 28 MB | z0-7 · **22 MB** | z0-12 · **16 MB** |
| seascape | z0-6 · 13 MB | z0-5 · **4.8 MB** | z0-10 · 54 MB |
| land | z0-9 · 14 MB | z0-6 · ~5 MB *(estimated, unmeasured)* | — |
| **total** | **55 MB** | **~32 MB** | **16 MB** without depth |

The seamap curve is ~2.7× per zoom worldwide (z7 22 MB, z8 60 MB); seascape is steeper
(world z5 4.8 MB, z6 46 MB). z7/z5 is the knee.

**Design:**

1. **World floor — bundled, ~32 MB.** Replaces `land-usca`, `seamap-natl`,
   `seascape-natl`. Buoys, lights, beacons and shaded water everywhere on earth. No
   blank tile is reachable.
2. **Home water — bundled, unchanged.** Salish z0-12, 41 MB.
3. **Region packs — downloaded.** US & Canada first (the existing 55 MB national cut,
   re-shipped as a pack), then UK & Ireland.

Bundle goes 104 MB → **~73 MB**, covering the planet instead of one continent. The
US+Canada regression (z9 → z7 outside the Salish box) is restored by the pack, which is
also what proves the download path on tiles we have already built and validated.

### Delivery

`URLSession` background download from `tiles.openwaters.io` into Application Support.

Rejected: **On-Demand Resources** — the OS purges ODR assets under disk pressure, which
silently breaks the one promise the app exists to keep. **Background Assets** — a
separate extension target and an asset-pack pipeline for what is one file copy, and it
couples pack updates to app releases.

App-side change is small. Every tileset resolves through `Bundle.main.url(forResource:)`
(`MapScreen.swift:374`, and `pmtilesUrl` at :546). One resolver that checks the packs
directory before the bundle covers all of it.

**Free fallback:** PMTiles is range-addressable over HTTP, so a region with no pack
downloaded still draws *online* by pointing MapLibre at the remote archive. Offline is
the pack's job; online is free.

## 3. The UK stations do not ship until they are validated

The README's rule is `coverage stops where we can still tell when the numbers are wrong`.
`gen-tides.mjs:~180` documents exactly why that bites here:

> TICON computes datums against the current epoch rather than an agency's adopted chart
> datum and drifts 0.2-0.4 m on this coast

That finding is why TICON cedes to CHS inside `CHS_COVERAGE_KM` in Canadian water, and why
`slackwater-web` was deliberately left on the narrow gate. **The UK rows are the same
TICON data with the same exposure** — Avonmouth carries `LAT = -0.152`, Arun Platform
`+0.123`, i.e. the drift band is already visible in the bundle.

The market research is corroborating, not theoretical: the Tide Guide teardown records UK
reviewers reporting wrong times *and* wrong datums, "by a margin that could pose navigation
risks", including south-coast double high waters. That is the review we would inherit.

So: **spot-check TICON predictions against published UK tide tables (EasyTide / Admiralty)
for a representative dozen ports before any UK station ships.** Cover at least one
double-tide port (Southampton or Poole) — `Station.swift:53` computes the Doodson
criterion `(M4+MS4)/M2 > 0.25` from constituents, so the mechanism exists, and the Solent
is where it either works or is caught.

**Proposed pass bar, over a full springs-to-neaps cycle:** high- and low-water times
within **±15 min**, heights within **±0.3 m**. The height figure is deliberately just
outside the documented 0.2–0.4 m TICON drift band — a station that only fails on a
constant offset is a datum problem with a per-station fix (the `signalk-tides` work
established exactly this shape for CHS LAT), whereas one that fails on *timing* is a
constituent problem with no cheap fix. The validation run confirms or moves these
numbers; it does not assume them.

Stations that fail validation do not ship as numbers. Whether they ship as findable-but-
blank (the CHS treatment) is deferred until we know how many fail.

## 4. Debt this creates, named now

- **`COUNTRY_FIX` does not scale.** Seventeen hand-written rows correcting TICON's
  "operating agency = country" field. At 129 countries this needs deriving from position,
  not maintaining by hand. The `-usa-noaa` id suffix is the current tell. Ascension already
  arrives under `United Kingdom`.
- **`places.json` is US/CA only** — 9,660 towns. UK stations fall through to the upstream
  `region` field, which is populated ("England", "Scotland"). Accept the bare region line;
  do not build a world gazetteer for this.
- **Dedup is Canada-shaped.** `DUPLICATE_KM = 1.0` and the TICON-vs-CHS cede logic assume
  two publishers. The UK has four overlapping ones (`bodc`, `cco`, `noc`, `da_idh`) on the
  same harbours, and three `Ascension` rows are already visible in the raw data.
- **Two hard `throw`s will fire** — `stations.length < 1300` (line 352) and "a station has
  no region line" (line 356). Both are correct guards; both need their thresholds revisited
  as coverage changes shape.
- **Victoria-anchored defaults:** `SALISH_CENTER` (`MapScreen.swift:13`), `fallbackFix`
  (`LocationService.swift:10`), `fridayHarborID` (`TideStation.swift:26`). These need to
  follow the fix or the last-used station.
- **`slackwater-web` stays on the narrow gate** — still a Salish bbox, and
  `chartTicks.ts:4` assumes UTC whole hours equal local whole hours (true for
  `Europe/London`, false for `America/St_Johns`, which is already in the iOS bundle).
  Separate work, not this spec.

## 5. Explicitly out of scope

**Currents.** TICON supplies zero current stations, and `current-stations` is a NOAA
CO-OPS scraper end to end. UK tidal streams are UKHO Crown copyright and have never been
analysed — the entire record is one deferred bullet in the 2026-07-12 spec. The app's
wedge is currents, so shipping tides-only into the UK ships the commodity half, and the
UI must say so rather than imply coverage it does not have.

Research into a UK/European currents path is complete and lands in
`docs/research/european-currents-licensing-2026-08-16.md`. Headline: there is a viable
path, it is a per-country licensing exercise, and no global model reaches the gates.
Germany's BSH stream atlas is free and commercially licensed today; France's currents are
Licence Ouverte 2.0; the UK's free route is fitting constituents from CMEMS/Met Office
AMM15 at 1.5 km, which we would own. Authoritative UK streams need a UKHO commercial
licence whose price is unpublished.

## Success criteria

1. **DELIVERED (corrected).** Slackwater opened in the Solent lists **Portsmouth,
   Lymington and Bournemouth** in Near Me, with heights and extremes that match the
   validation tolerance agreed in §3. (As written this criterion named Cowes and Poole;
   neither exists in `@neaps/tide-database`. These three are what the acceptance test
   asserts.)
2. **PLAN B — not built.** The map draws a real chart at every zoom, anywhere on earth,
   with no pack downloaded.
3. **PLAN B — not built.** "UK & Ireland" downloads and the Solent draws at Salish-grade
   detail offline, with the device in airplane mode.
4. **PLAN B — not built** (the bundle-size ceiling on the pack work above). Bundle size
   does not exceed today's 104 MB.
5. **DELIVERED.** Nothing claims current coverage in UK waters.
