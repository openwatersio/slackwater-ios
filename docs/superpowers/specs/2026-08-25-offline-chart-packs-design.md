# Offline chart packs: hosted tiles + automatic tiered downloads replace the bundled chart

**Owner rulings (2026-08-25/26 session):** map data adopts the CHS model — fetched from the network, cached for offline, honest when absent. Downloads are automatic, not a picker. First run may assume network — the app itself arrives over it — so **nothing chart-shaped is bundled**. Attribution is handled by showing it properly (map surface and/or a licenses page), not by stripping sources. Packs are built against the existing `?shading=bands` style variant, with the DEM sources stripped app-side (§2).

Consumes: the hosted styles at `https://tiles.openwaters.io/seamap/style.json` and `/seascape/style.json` (seamap's carries the full stack — VersaTiles shortbread basemap, seamap + seascape vector, hosted glyphs, chart sprite), MapLibre Native's offline machinery (`MLNOfflineStorage`, `MLNTilePyramidOfflineRegion`), and the existing managed-download surface (`OfflineDownloads.swift`: `OfflineManagerView`, `Connectivity`, per-item ready/stale/waiting states).

Resolves: #35 (style swap loses chart marks — dissolves structurally, see §1), #122 for chart data (data fixes without app builds), #30 (chart coverage beyond the Salish box), #8 (region packs — superseded by automatic tiers). Touches #29 (bundled glyphs become pack-downloaded glyphs).

## 1. The model: one style, offline-ness is a cache property

Today the app carries two rival charts: ~108 MB of committed PMTiles composed into a local fallback style, and a remote style that *replaces* it when the network appears (`MapStyler.fetchSeascape` → `setStyle`). That rivalry is the root cause of #35: gaining signal swaps the chart and loses the seamap marks; a marginal link swaps to a style whose tiles then stall.

In this design there is **one style — the hosted one** — and offline capability comes from MapLibre's offline packs: the app registers regions (style URL + bounds + zoom range) with `MLNOfflineStorage`, MapLibre downloads every tile, glyph, and sprite those regions need into its cache, and rendering transparently serves from cache when the network is absent. No style swap exists to get wrong. What #35 called "worth confirming" — that Native tolerates a source whose tiles never arrive without dropping the layers above it — becomes a §7 acceptance gate, because "tiles not yet downloaded" is this design's steady state at the world's edges.

The app's style-composition step survives. MapLibre's cache is keyed by resource URL, so a locally composed style (filtered to `nativeLayerTypes`, fill layers inserted under land, `CurrentFill.addFillStyle`) that points at the same tile URLs hits the same cache the packs filled. Composition changes from "assemble bundled slices" to "fetch the hosted style, transform, serve from the cached copy when offline" — the transform pipeline in `MapScreen.composeStyle` is the part that stays.

## 2. The style variant: `?shading=bands`, DEM stripped app-side

The hosted seascape style already takes `?shading=bands` (valid values: `relief` | `bands`). Verified against the live endpoints (2026-08-26): bands caps the `depth-shading` color-relief layer at maxzoom 6 and widens the `depth-areas` fill filter, so depth portrayal becomes banded vector fills — which matters doubly here, because **MapLibre Native rejects `color-relief` layers outright** (`MapScreen.swift:606-610` filters them today). Bands is the portrayal that actually renders on Native; relief never has.

Two residuals the param does not cover, both handled app-side in the existing composition step:

- **The raster-DEM sources stay declared** (`seascape-dem`, and `elevation` on the seamap style) along with their hillshade layers. An offline pack downloads every source its style references, so packs must be registered against the app's **composed** style with the DEM sources and their layers stripped — the same pass that already filters to `nativeLayerTypes`. Otherwise raster-DEM tiles Native never renders dominate every pack's byte count.
- **`seamap/style.json` currently ignores `shading`** (byte-identical output with and without it); only the seascape endpoint honors it. Either the app keeps composing seamap layers itself as today, or the seamap endpoint learns the param — not a blocker either way.

§7 gate 1 verifies the stripped composed style is what packs actually fetch against.

Attribution: with no licence conflict to engineer around, the app shows proper attribution for VersaTiles/OSM/chart sources — MapLibre's attribution button fed from the style's `attribution` strings, plus a licenses entry in Settings. The `osm-base`-stripping step in `composeStyle` retires once attribution is in place.

## 3. No bundled floor — first run assumes network

Installing the app requires the network; the first launch can require it too. The world pack (§4) starts downloading the moment the app first runs — a few hundred tiles, seconds on any connection — and from then on the cache guarantees the map is never blank. That world pack *is* the floor.

The truly offline first launch (a restore or re-install at sea) degrades honestly and recovers on its own: the map renders the `WATER_TONE` background plus everything that never needed tiles — station pins (client-side GeoJSON) and the current fill (bundled harmonics) — and the packs download when the network returns. No bundled tiles, no fallback style, no sideloaded cache.

Everything chart-shaped bundled today — `seamap*.pmtiles`, `seascape*.pmtiles`, `land.pmtiles`, `land-usca.pmtiles`, sprite JSON/PNGs, glyph PBFs — leaves the app target. The install shrinks by roughly 100 MB.

## 4. Automatic tiered packs

Downloads happen without being asked. Three tiers, each mapping to persistent, individually deletable `MLNOfflinePack`s:

| Tier | Region | Zoom | Trigger / lifecycle |
|---|---|---|---|
| World | whole world | z0–4 | created on first launch; refreshed opportunistically |
| Area | one pack per z5 grid cell | z5–8 | a cell pack exists while the cell is in the 3×3 set around the GPS fix **or** contains a starred/downloaded station; cells that satisfy neither are deleted |
| Station detail | the grid cell(s) intersecting a ~20 km disc around each starred or downloaded station | z9–12 | created when starred, deleted when unstarred. Kept a self-contained module a config flip can turn off (owner ruling: the map is orientation, not navigation — cache size, not feature completeness, decides whether this tier survives; §7 gate 4 records the visual cost of dropping it) |

Each tier owns its zoom range outright — world owns z0–4, the area cells own z5–8 everywhere they exist, station packs are always exactly z9–12 — so no zoom level is ever downloaded twice for the same ground, and no pack's zoom range depends on what its neighbors cover. Starring a station therefore creates two things: its z9–12 detail pack, and (if absent) the z5–8 area pack for the cell it sits in. Grid alignment is what makes the bookkeeping trivial: packs are keyed by tile coordinate, so they either exist or don't, moving downloads only genuinely new cells, and two starred stations in one cell share the area pack. No rolling boxes, no overlap math, no hysteresis margin to tune: cell edges are the hysteresis. A z5 cell is ~1,250 km across at mid-latitudes (~85 tiles per source at z5–8); if §7's byte counts say that's too generous, the identical design on a z6 grid (~625 km) is the dial.

Zoom rationale — calibrated against what the bundled tilesets already ship, since those numbers were picked for the same trade:

- **Vector tiles overzoom losslessly.** Capping download zoom costs features the tileset only emits at deeper zooms (tippecanoe-style thinning), never sharpness. The hero renders at `stationZoom` 12.5 from z12 data today; that keeps working.
- **z12 is the detail terminal.** The bundled detailed slices are built to z12; treat that as where seamap's point layers (buoys, lights, rocks) are complete unless §7's completeness check says a lower zoom already has everything.
- **z8 for the cruising tier** clears `depth-areas`' `minzoom: 6` with headroom, so a wide area gets real bathymetry and major marks.
- **Small station footprints at z12.** A z12 tile is ~10 km across; the cells covering a 20 km station disc hold ~25 z12 tiles per source (~35 across z9–12), so 50 starred stations is low thousands of tiles. Blanketing the whole cruising area at z12 instead would be ~1,500 tiles per source per z5 cell — the per-station footprint is what keeps the detail tier affordable.

Mechanics:

- `MLNOfflineStorage.setMaximumAllowedMapboxTiles` is raised (self-hosted, no contractual ceiling); the default ~6,000 would be hit by the tiers combined.
- Packs download over any network by default; a cellular-pause switch can ride the offline manager if usage says it's needed (YAGNI until then).
- Each tier surfaces in `OfflineManagerView` as chart rows beside the CHS gates, with pack progress notifications feeding the same ready/downloading/waiting presentation. No new UI surface.
- Staleness: packs refresh opportunistically (MapLibre re-validates cached resources); a manual "refresh charts" affordance in the offline manager covers the sailor who wants the newest chart before departure.

## 5. App-side changes

- `MapStyler` (`MapScreen.swift`): `localFallbackStyle` retires; `fetchSeascape`/`composeStyle` becomes the single style path (fetch hosted Native-variant style → transform → cache the composed JSON → `styleURL`, with the cached composed copy serving when offline). The two-styles-per-session dance and its re-attach choreography (`applyChsTones`, `CurrentFillRenderer.attach` re-running per style load) simplify to one load in the common case.
- A small `ChartPackManager` owns tier lifecycle: observes first-launch, GPS fix movement, and `FavoritesStore` changes; creates/deletes packs accordingly; publishes state for the offline manager rows.
- `project.yml` / `Slackwater/Resources`: the PMTiles and glyph/sprite resources leave the app target; nothing chart-shaped replaces them.
- The camera-reassert-on-style-load bug (`MapScreen.swift:726` ponytail note) matters more when the style arrives late over the network — fix it as part of this work, not after.

## 6. Explicitly unaffected

- **Current fill and patches**: `FillField`/`PatchField` evaluate bundled harmonic bundles on-device — app data, not tiles. They ship exactly as today and render over the water-tone background even with zero chart packs.
- **Station pins**: generated client-side from the station catalog into a GeoJSON source; no tiles involved.
- **CHS fits, tide engine, widgets**: untouched.

## 7. Measurements and acceptance gates

Empirical gates, in order, before committing to the tier constants:

1. **Gate 1: Packs fetch against the stripped composed style** (§2): observe a pack download and confirm zero requests to the raster-DEM sources. This also proves MLN accepts a locally composed style as a pack's style URL — if it insists on a remote style URL, the fallback is a server-side variant that omits the DEM sources.
2. **Gate 2: World-tier byte count** — RUN (2026-08-26, live endpoints, n=64/zoom sampling, zero errors). World z0–4 for the full stack: **27.7 MB** (shortbread 7.2, seamap 10.6, seascape-vector 9.3 — its z0 tile alone is 1 MB of global contours — coverage 0.5). Alternatives priced for comparison: versatiles dark (same shortbread tiles, dark paint) 7.2 MB; versatiles satellite (raster) 8.6 MB.
3. **Gate 3: Area-cell and station byte counts** — RUN, same session. Full stack per z5 area cell (z5–8): **11.4 MB**, measured on near-worst-case cell 5/11 (Seattle, Vancouver, Portland, inland to Utah; ocean cells are near-free). Station box (z9–12, Deception Pass): **4.3 MB**, of which seascape-vector is 2.8 and seamap only 0.8. Steady state (world + 3×3 cells + a station): full stack ~**134 MB** — about today's bundle, but as self-updating cache covering the user's actual location plus a world floor; dark ~40 MB; satellite ~46 MB (through z12 only; raster grows steeply past that). **Bathymetry is the size lever**: if trimming is wanted, cap seascape-vector's pack zoom (banded fills overzoom acceptably for orientation) before touching seamap; the z6-grid dial (~4× smaller 3×3 footprint) is the other knob.
4. **Gate 4: Seamap completeness by zoom** — RUN (2026-08-26, against the bundled `seamap.pmtiles`, central Salish box 47.8–48.8°N / 123.3–122.2°W, unique in-box points deduped across tile buffers). Aids to navigation are complete at z8: lateral beacons 138/139, lateral buoys 95/96, special-purpose buoys 77/77, landmarks 138/139. **Hazards are not**: rocks are 86 of 722 at z8 (12%), 334 at z10 (46%), 524 at z11 (73%), complete only at z12; piles 1,573/2,158 at z8. Interpretation under the owner's framing — **the map is orientation, not navigation** — is that incomplete rocks at z8 are tolerable, not disqualifying: the tier's fate rides on gates 2–3's byte counts, with this data saying only what turning it off would cost visually. (Measured on the bundled slice; re-confirm against the hosted tileset once packs fetch from it — same pipeline, so divergence would itself be news.)
5. **Gate 5: Missing-tile behavior**: with a pack absent, pan into un-downloaded water and confirm Native renders whatever zoom levels the cache holds (overzoomed if need be) over the water tone, without dropping styled layers or erroring (the #35 open question).
6. **Gate 6: First-run behavior**: with network, the world pack downloads without being asked and the chart appears within the first session. In airplane mode, the map renders water tone + pins + fill without erroring, and the packs download unprompted when the network appears.
7. **Gate 7: The existing offline UI tests** (station data offline flows) pass unchanged — chart packs must not entangle with CHS download states.

## 8. What this deletes

- ~100 MB of committed PMTiles/sprites/glyphs from the app bundle.
- The fallback-vs-remote style rivalry and #35 with it.
- `tools/build-seamap.sh` / `build-seascape.sh` / `build-land.sh` stop producing app resources; their job shifts to publishing the hosted tilesets (the `tile-join` traps documented in `CLAUDE.md` move with them).
- Issue #8's deferred region-picker UX: superseded — automatic tiers, no picker.

## 9. Phasing

**One PR, all or none (owner ruling, 2026-08-26).** The migration is atomic: the map switches to the VersaTiles satellite raster (plus the app's own pins and fill), `ChartPackManager` and the tier lifecycle land against it, `MapStyler` collapses to that single pack-backed style path (#35 dies here), and the bundled tilesets leave the app in the same PR (~100 MB lighter). No transitional dual system, no dormant safety net — reverting the PR is the rollback.

Satellite is the deliberate starting style: the cheapest possible proof of the pack mechanism — one raster source, no sprite, no composition, no DEM to strip — priced by the spike at ~46 MB steady state. Gates 1, 5, and 6 get answered by this PR. Swapping the pack style from satellite to the composed seamap stack (§2) is the follow-up PR; the tier code doesn't change, only the style the packs are registered against, and offline manager rows land there if pack visibility is wanted.
