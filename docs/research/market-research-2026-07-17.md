# Slackwater — iOS Tides & Currents Market Research

*2026-07-17. Deep-research sweep: 5 search angles, ~20 primary sources (live App Store
listings, developer homepages, PNW boating forums, open-data references), adversarial
verification on the highest-stakes claims. Ratings/prices are US App Store as of 2026-07.*

*Verification note: claims marked ✅ survived 3-vote adversarial verification against the
live primary source. Unmarked facts come from direct primary-source fetches whose
verification votes were cut short by a session limit — treated as reliable (they're
verbatim App Store extractions) but not adversarially confirmed.*

## 1. The landscape in one table

| App | Links | Tides | Currents | Offline | Pricing | Widgets/Watch | Data / OSS stance | Rating (US) |
|---|---|---|---|---|---|---|---|---|
| **Tides Near Me** | [App Store](https://apps.apple.com/us/app/tides-near-me/id585223877) · [tidesnear.me](https://tidesnear.me) | ✔ | Partial — station current direction/timing | Only after cache; not offline-first | Free + ads; Premium IAP $14.99 (30-day forecasts, no ads) | Widgets + Watch w/ complications | Proprietary; NOAA-sourced | 4.8★ · ~159K |
| **Tide Alert (NOAA)** | [App Store](https://apps.apple.com/us/app/tide-alert-noaa-tide-chart/id1352211125) · [tidealert.app](https://tidealert.app/) | ✔ | Partial ✅ — current speed + *estimated* slack windows overlaid on tide chart | Month tables + favorited stations offline | Free + sub: $6.99/3mo, $19.99/yr, $99.99 lifetime | Widgets (home+lock) + full Watch app + Siri | Proprietary; NOAA only (no CHS) | 4.8★ · ~44K |
| **AyeTides / AyeTides XL** | [App Store](https://apps.apple.com/us/app/ayetides-xl/id383466582) · [hahnsoftware.com](https://www.hahnsoftware.com/products_page/ayetides/) | ✔ | ✔ ✅ — real harmonic current stations (12,500+ locations tides *and/or* currents; currents a subset, sparse in BC) | ✅ **Fully offline predictions** (XTide lineage; map/sharing need network) | ✅ **$7.99 one-time**, no ads, no IAP | Widgets + Watch + station map; iNavX/SEAiq integration | Proprietary app on XTide/NOAA harmonics + licensed station DB | 4.8★ · ~1.3K (XL); shipping since ~2010 |
| **Actual Currents** | [App Store](https://apps.apple.com/us/app/actual-currents/id6761431005) · [actualcurrents.com](https://www.actualcurrents.com/) | ✗ (currents-first) | ✔ ✅ — animated particle flow on ENC charts, NOAA ADCIRC model harmonics + PORTS; CHS *station points* added v2.04 (Jun 2026); Salish-Canada extent undocumented | ✅ **None mentioned — online/streaming model** | Free (±3h window only) + $4.99/mo or $39.99/yr (7-day trial) | ✅ None mentioned | Proprietary; NOAA ADCIRC + CHS | 4.8★ · 16 (launched Apr 2026) |
| **Tides and Currents-USA** | [App Store](https://apps.apple.com/us/app/tides-and-currents-usa/id6464309360) | ✔ (1,343 harmonic + 2,199 subordinate) | ✔ — **849 harmonic + 1,707 subordinate current stations** | Full offline harmonic calc, any date | Free + Pro $2.99/mo, $19.99/yr, $49.99 lifetime (date range, monthly tables, forecast maps) | — | Proprietary; NOAA harmonics; US-only | 4.1★ · **24** — janky UX (broken station picker) |
| **PNW Current Atlas** | [App Store](https://apps.apple.com/us/app/pnw-current-atlas/id1456020312) (TinyOctopus.net) | ✗ | ✔ — CHS current-atlas *charts* (San Juans, Gulf Islands, E. Juan de Fuca), any date/time | ✔ Fully offline, year bundled | Free 3-day trial + $19.99 one-time (year's charts) | — | Proprietary; **licensed CHS atlas data** | 3.5★ · 32 — timing-accuracy complaints |
| **DeepZoom** | [deepzoom.com](https://deepzoom.com/) — **web only, no iOS app** ✅ | ✔ | ✔ — the PNW favorite for animated NOAA current maps; new trip-planning tool | ✗ (web) | Free | ✗ | Proprietary (public-assets repo only); NOAA + some CHS-derived | n/a |
| **CurrentlyBC** *(added 2026-07-19, [r/boating announce](https://www.reddit.com/r/boating/), ~2026-05)* | [currentlybc.com](https://currentlybc.com/) — **web only, no app to download** | ✔ | ✔ — tides *and* currents together on one map; scrubbable timeline, click a station for its chart, chart→table toggle | ✗ (web app, no offline claim) | ✅ Free, no ads, no account/login, non-commercial | ✗ | Proprietary (solo/hobby, gmail contact); **CHS/DFO under [OGL-Canada](https://open.canada.ca/en/open-government-licence-canada) + NOAA CO-OPS** (US gov, public domain); basemap OpenFreeMap/OpenMapTiles/OSM — the only competitor besides ours leading with both nations | n/a (new) |
| **Lunitidal** *(added 2026-07-20)* | [lunitidal.app](https://www.lunitidal.app/) · [vinc3m1/lunitidal](https://github.com/vinc3m1/lunitidal) — **web only**, installable PWA | ✔ worldwide | ✗ — tides + waves/swell only | ✅ **Offline-first** — harmonics computed in-browser, installable; only forecast/search need network | ✅ Free, no ads, no account | ✗ (PWA install only; no widgets/Watch) | ✅ **MIT, fully open source** (Vince Mi); **TICON-4 / UHSLC via the Neaps tide-database**, Open-Meteo waves, OpenFreeMap/OSM | n/a (new, 2 ★) |
| **XTide (iOS)** *(added 2026-08-21)* | [App Store](https://apps.apple.com/ca/app/xtide/id1191127595) · [note](xtide-ios-2026-08-21.md) | ✔ | ✔ (XTide harmonics) | ✅ Fully offline | ✅ Free, no ads, no IAP, zero data collection | Watch + widgets + complications | Lee Ann Rucker's revival of the 2005 TideApp port; open XTide/NOAA harmonics; **US-only** ("legal data restrictions") | too few ratings to show · **stale: v2.0.3, Mar 2023** |
| **Apple Tides (watchOS 26 stock)** *(added 2026-08-21)* | [r/AppleWatch feedback thread](https://www.reddit.com/r/AppleWatch/comments/1p8lxsx/tides_app_on_apple_watch/) | ✔ beaches only | ✗ | ? | Free (built-in) | Watch-native | Apple first-party, surf-beach framing | n/a — thread verdict: obscure (users find it by accident), defaults to Mavericks/Waikiki/Bondi, nearest-beach discovery flaky, search misses beaches <10 mi away, no lakes |
| **Tide Tracker (tidetracker.io)** *(added 2026-08-21)* | [tidetracker.io](https://tidetracker.io/) | ✔ | ✗ | ✗ web-only | Free | ✗ | Bay Design Associates (a Berkeley YC member); NOAA; US-only | n/a — praised in [r/sailing thread](https://www.reddit.com/r/sailing/comments/1tf41qd/sailors_what_would_make_your_tide_app_actually/) for **state-first UI** ("first thing you see is the current tide state") — validates our state-first answer shape |
| **OceanConnect** | [oceanconnect.ca](https://oceanconnect.ca) ([Hakai](https://hakai.org/free-ocean-conditions-app-for-the-salish-sea/)) | ✔ | ✔ — UBC *model* current maps ~40h out, Olympia→SE Alaska | ✗ online-only | Free | — | Model-based (not harmonic), Canadian side strong | niche |
| **qtVlm** *(added 2026-07-18, [48north](https://48north.com/news/new-tidal-current-resource-for-swiftsure-and-r2ak-sailors/))* | qtvlm.com (desktop) | ✔ | ✔ — **NOAA OFS model** currents via internal GRIB server ("all locations, all times"), 4×/day + hourly 2–3 day; feeds **current-aware route optimization** with HRRR winds | Once GRIBs/charts downloaded (desktop) | App free; **OFS GRIB service free to 2026-05-15 then subscription** | ✗ (Mac/PC only) | Proprietary; NOAA OFS + HRRR, ENC charts | n/a (desktop) |
| **SEAiq** | [seaiq.com](https://www.seaiq.com) · [tide docs](https://doc.seaiq.com/TideHelp.html) | ✔ | ✔ — XTide currents, S-111 surface currents, set/drift (Pilot tier) | ✔ XTide offline + NOAA/CHS pre-download | Free + paid editions; Pilot tier gates advanced | — | Proprietary nav app **on open XTide data** ("NOT FOR NAVIGATION" disclaimers) | pro niche |
| **Nautide** | [nautide.com](https://nautide.com) | ✔ 15,000+ stations | ✗ | 3-day offline cache only | Free + paid content | — | Proprietary | mass-market |
| **Tide Guide** *(not in this sweep — from spec/prior research)* | [tideguide.com](https://tideguide.com) | ✔ | Partial (US) | Partial | Sub (Pro tier) | Best-in-class widgets/Watch/Live Activities | Proprietary; NOAA-centric, weak CHS accuracy (our spec's #1 wedge vs them) | design leader |
| **Navionics / chartplotters** | garmin.com | ✔ | Station icons, but forum-verified: **currents not integrated into routing** | Chart-dependent | Sub | — | Proprietary | incumbent default |

## 2. What makes the successful ones successful

- **Instant answer at launch.** Tides Near Me's 159K ratings come from one interaction:
  open app → nearest station → tide now/next. Zero setup. Review themes across both
  mass-market leaders: *simplicity, reliability, location-based*.
- **Alerts as identity.** Tide Alert's namesake feature (notify at custom tide level) built
  a 44K-rating app. Alerts are retention: the app pings *you*.
- **Widgets + Watch are table stakes** in every 4.8★ app (Tide Alert, Tides Near Me,
  AyeTides all ship both; Tide Guide leads here).
- **One-time-price loyalty.** AyeTides has held $7.99-no-subscription for ~15 years —
  its forum reputation ("the one boaters keep") is inseparable from that. Prosumers
  resent subscriptions for deterministic math.
- **Longevity + trust beat features.** PNW Current Atlas (3.5★) proves Salish currents
  demand exists *and* that timing-accuracy complaints kill a niche app. Accuracy is the
  moat claim that must be provable — our golden-vector positioning is right.
- **Currents remain the unsolved problem.** Forum consensus (Sailing Anarchy, Trawler
  Forum, WestCoastPaddler, sailboatowners): people cobble DeepZoom (web) + chartplotter +
  printed Ports & Passes. Navionics "doesn't use tides or currents for navigation at all."
  BC paddlers note even AyeTides has *sparse, sometimes mislocated* BC current stations.

## 3. The currents gap, precisely

Nobody ships **offline + real current predictions + US-and-Canada + modern UX**:

| Contender | Why it doesn't close the gap |
|---|---|
| AyeTides | Offline+currents ✔ but dated UI, sparse/buggy BC current stations, no slack-window planning |
| Actual Currents | Beautiful currents ✔, CHS points ✔ — but **online-only, subscription-gated to ±3h free**, no widgets/watch, US ADCIRC model core |
| Tides and Currents-USA | Offline harmonic currents ✔ — US-only, 24 ratings, broken UX |
| PNW Current Atlas | Offline Salish currents ✔ — atlas pictures not station predictions, one region, accuracy complaints |
| DeepZoom / OceanConnect | The UX/coverage references — both require connectivity, neither is an app |
| CurrentlyBC | Closest coverage match (CHS+NOAA, Salish/San Juans/Puget, tides+currents at once) and free with no ads — but **web-only, online-only, no widgets/Watch/alerts**. Design is decent, not a benchmark. Its existence validates the coverage thesis; being a browser page leaves the offline mobile lane open. Useful as a live reference for map-based tide+current UX since the website *is* the product. ⚠️ Its info panel states "Times are BC local time (UTC−7 all year)" — BC still observes DST, so that reads **an hour off in PST**; re-check in November before citing it as an accuracy foil |
| Lunitidal | The one that gets *offline* right on the web — in-browser harmonics in an installable PWA, MIT, free — but **no currents at all**, and tide-only is the crowded half of the market. Its Victoria heights come from TICON-4/UHSLC (not CHS), which is exactly the datum-accuracy line our CHS wedge is built on. Closest match to our open-source posture; not a competitor for the currents lane |
| qtVlm | Model OFS currents + real routing ✔ — but **desktop-only, online GRIB fetch, subscription-bound**: a racer's nav-station router, not a mobile quick-answer / offline slack-window tool. Different device and occasion. |
| Tide Alert | Slack windows are "estimated" overlays on a tides app, US-only |

### CurrentlyBC's map, observed (2026-07-19 screenshot)

One map, two mark types, one time control:

- **Tide stations = teardrop pins** with the height (ft/m toggle top-right). **Currents =
  arrows** where heading is set, the label is knots, and **arrow size scales with speed** —
  Seymour Narrows and Sechelt read as big black slabs from across the room. That size
  encoding is the good idea worth stealing: speed is legible pre-attentively, before you read
  a single number.
- **Timeline scrubber** across the bottom — hour ticks, draggable handle showing the selected
  datetime, and a red **Now** button to snap back. Days out, not just today. This is the
  "big-picture flow through the whole coast, at a time I choose" interaction, and it's the
  thing no offline tides app does.
- **Tides / Currents toggles** top-right — either layer alone or both at once.
- ⚠️ **It falls apart exactly where we care.** From Nanaimo south — Gulf Islands, San Juans,
  Puget Sound — arrows and labels collide into an unreadable pile; Race Passage, Porlier,
  Active Pass are all inside the mush. The coast-scale view is genuinely lovely and the
  transit-planning scale is unusable. No decluttering, no zoom-dependent thinning.
- ⚠️ **Two color families with no legend.** Some current arrows are navy, some red (presumably
  flood vs ebb), and tide pins are also red. The info panel documents units and timezone but
  never the color encoding — you infer ebb/flood or you don't.

Read together: their map answers *"what is the whole coast doing at 16:33?"* and never answers
*"can I get through this pass, and when."* That's the same line as everything else in §3 —
visualization, not a planner — but it's now visible rather than inferred.

**Actual Currents (Apr 2026) is the one to watch** — same instinct (currents-first,
NOAA+CHS), venture-style subscription. Slackwater flanks it on exactly its verified
weaknesses: offline (it has none), free offline core (its free tier is ±3h), boat-relative
slack windows (it visualizes flow, doesn't plan transits), widgets/watch (none).

## 4. Open-data substrate (verified)

- **XTide** ([flaterco.com/xtide](https://flaterco.com/xtide/)) computes tides **and
  currents** from harmonics; US NOAA current-station harmonics exist in the free file;
  ~1-min typical deviation from official tables; canonical "NOT FOR NAVIGATION" posture.
  Non-US data no longer maintained upstream.
- **Neaps tide-database** ([openwatersio/tide-database](https://github.com/openwatersio/tide-database)):
  MIT code, CC BY 4.0 station data, ~3,400 NOAA stations auto-refreshed monthly, 7,600+
  worldwide (TICON-4 — note: TICON/GESLA licensing is "mixed, not fully spelled out";
  ship NOAA-derived only to stay clean). **Tide heights only — no current harmonics, no CHS.**
  **Lunitidal ships the TICON-4 set globally in an MIT PWA** — a live precedent that someone is
  shipping it publicly, but it's precedent for the *mixed-licence* half we chose not to bundle,
  and its BC heights are TICON-derived rather than CHS.
- **CHS IWLS API** ([tides.gc.ca](https://tides.gc.ca/en/web-services-offered-canadian-hydrographic-service)):
  free under license, predictions + *currents at some stations*; **constituents must be
  leased** — our fetch-and-cache-per-user design is confirmed as the only clean path.
  Rate limits 3 req/s, 30 req/min: prefetch jobs must batch politely.
- **OGL-Canada attribution precedent**: CurrentlyBC ships CHS tide *and current* predictions
  publicly under the Open Government Licence – Canada with a plain attribution line ("contains
  information licensed under the OGL – Canada. Tide and current data © Canadian Hydrographic
  Service, Fisheries and Oceans Canada"). Confirms a live, unchallenged example of the
  fetch-and-serve-predictions path — the *constituent leasing* constraint above still applies
  to bundling harmonics offline, which is the harder thing we're doing.
- **Current-station NOAA harmonics** for bundling: XTide's free US file carries them
  (that's what AyeTides/SEAiq/Tides-and-Currents-USA compute from); Neaps DB does not —
  engine work must ingest current constituents from NOAA/XTide-format sources directly.

## 5. Pricing anchors

| Model | Who | Number |
|---|---|---|
| One-time prosumer | AyeTides XL | $7.99 |
| One-time niche | PNW Current Atlas | $19.99 (per year's data) |
| Sub mass-market | Tide Alert / Tides and Currents-USA | $19.99/yr |
| Sub currents-premium | Actual Currents | $39.99/yr |
| Lifetime | Tide Alert Gold / T&C-USA | $99.99 / $49.99 |

Slackwater's free-forever offline core undercuts every free tier in the table (all of
which gate date range, ads, or ±3h windows). Paid tier at $19.99–29.99/yr for live
overlays + alerts sits inside the established band.

## 6. Gap analysis vs the Slackwater spec

Spec: `2026-07-12-tide-app-design.md`, `2026-07-13-current-detail-view-design.md`
(in the Slackwater planning repo's `docs/superpowers/specs/`).

### Confirmed right — keep
- **Offline-first + currents + CHS wedge**: no competitor closes it (§3). Positioning validated.
- **Free unlimited-date offline core**: every freemium competitor gates date range. Differentiator.
- **Accuracy-first phasing / golden vectors**: the niche's graveyard is accuracy complaints.
- **CHS fetch+cache, no bundling**: independently confirmed as the only licensing-clean path.
- **"Not for navigation" disclaimer**: universal norm, spec has it.
- **Boat-relative slack windows / go-windows**: nobody has this. Tide Alert's "estimated
  slack" is the closest and it's an annotation, not a planner. This is the killer feature.
- **Near Me + state-first hero readout**: matches exactly the launch-to-answer behavior
  that made the 4.8★ mass-market apps.

### Gaps in the spec — address
1. **Local (offline) threshold alerts are misfiled as paid/server.** Spec puts "push
   threshold alerts" in the paid tier as server-dependent. But our predictions are
   deterministic — *scheduled local notifications* ("slack at Race Passage 14:32",
   "tide below X ft at 16:10") need **no server**. Tide Alert built a 44K-rating app on
   alerts; we can ship them offline, free, as a headline feature. Reserve the paid tier
   for alerts on *live observed* data (weather, surge, real-time deviations). This is the
   single biggest spec correction from the research.
2. **Widgets + Watch are table stakes, not polish.** Spec defers to "Phase 1+…then
   widgets/complications." Every 4.8★ competitor ships both; reviews name them. Pull
   widgets (at minimum: next slack / next high-low, home + lock screen) into the MVP
   definition of done; Watch can trail but not by much. (Live Activity backlog item #1
   already covers the Dynamic Island story — it's a differentiator on top, not a substitute.)
3. **Current-station data quality is a landmine and an opening.** BC paddlers report
   AyeTides current stations sparse *and* mislocated ("clearly placed on land"). Add to
   Phase 0: audit BC/Salish current-station metadata (positions, flood direction) against
   CHS; a curated corrections layer is cheap and becomes a trust story.
4. **Engine: current harmonics source needs an explicit plan.** Neaps DB (our named
   source) has **no current constituents**. US current harmonics live in the XTide-format
   NOAA file; CHS currents via IWLS online. Spec §4 says "current-station predictions
   (slack/max)" but §8's data source can't deliver them — name the current-constituent
   ingestion path in Phase 0 scope.
5. **Tide Guide wasn't covered by this sweep** — the design benchmark deserves its own
   teardown (widgets/Live Activities especially) before Phase 1 UI work. Known from spec:
   iOS/Watch-only, subscription, weak non-US accuracy.
6. **Minor**: monthly tide-table view (offline month grid) is a recurring
   fisherman/planner feature (Tide Alert, T&C-USA Pro). Cheap once the engine exists;
   consider for the events-table workstream. Chartplotter-integration expectations
   (Garmin users default to their plotter) reinforce that our phone-as-redundancy framing
   is the right marketing angle, not a routing/nav feature race.

### Non-gaps — explicitly skip
- Route/passage current integration (Coastal Explorer-style): forum-wanted but it's a
  nav-app feature; keep Slackwater a planning/redundancy tool. (Our currents-mcp/Poseidon
  stack already does passage planning on the boat side.)
- Global coverage marketing, ads, engagement gamification, model-based flow-field maps
  (OceanConnect/Actual Currents/**qtVlm** territory — server-heavy, off-brand for offline-first).
- Current-aware route optimization (qtVlm's Swiftsure/R2AK wedge) — a desktop nav-app race
  feature; same "keep Slackwater a planning/redundancy tool" line as passage integration above.
