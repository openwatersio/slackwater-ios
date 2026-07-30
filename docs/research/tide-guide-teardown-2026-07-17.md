# Tide Guide — Design-Benchmark Teardown

*2026-07-17. Gates Phase 1 UI work (spec §6). Sources: live App Store listing,
tideguide.com + /reviews, web sweep. Closes the gap the market-research sweep missed
(`market-research-2026-07-17.md` §6.5).*

## Identity

- **Tide Guide: Charts & Tables** — Condor Digital LLC (indie dev **Tucker MacDonald**,
  [tuckermacdonald.com/apps/tide-guide](https://www.tuckermacdonald.com/apps/tide-guide))
- [App Store](https://apps.apple.com/us/app/tide-guide-charts-tables/id1406371071) ·
  [tideguide.com](https://www.tideguide.com/)
- **4.7★ · ~9.4K ratings.** Apple Design Award winner, App Store App of the Year
  finalist, Editors' Choice. iPhone / iPad / Mac / Watch / Vision Pro. iOS 17+, 320 MB.
  15 languages. v7.3.12 (mid-July 2026) — actively shipped.

## Pricing — and the strategic read

Free + **Pro subscription**: ~$4.99/mo, ~$29.99/yr, **$150 lifetime**.

**Widgets, complications, detailed charts, and future table data are all paywalled.**
That's the top of the market charging for exactly what we plan to ship free. Reviews
say "the widgets alone are worth the subscription" — confirming widgets are the
retention surface — and Slackwater giving them away (deterministic math, no server
cost) is a direct, honest flank. Their $150 lifetime also anchors the category's
ceiling; our free core reads as radically generous against it.

## Feature inventory (what Phase 1 is benchmarked against)

- **Charts**: full-screen dynamic tide chart; press-and-hold for a moment's prediction;
  swipe forward/back across days; tap to switch the chart between conditions (tide /
  wind / swell). 10-day forecast; 12-month tide tables; monthly tables on Watch.
- **Weather bar**: 12+ live condition types (wind, swell height/period/direction, rain,
  temps) inline with the tide story — their real product is *tides + marine weather*.
- **Sun/moon**: lunar phase, moon altitude, solunar times, nautical dawn/dusk.
- **Widgets**: home + lock screen, heavily customizable (text-forward and visual
  styles, mix-and-match data points). Paywalled.
- **Live Activities**: follow the tide or sunset in Dynamic Island / lock screen, and
  — notably — **scheduled start**: pick a time of day and the Live Activity starts
  automatically without opening the app.
- **Watch**: full app, customizable complications, **works offline at the wrist**;
  monthly tables added in the latest release. Complications paywalled.
- **Siri Shortcuts**, extensive accessibility (200% text, high contrast), 15 languages.

## Where it's weak — our wedge, verified

1. **Currents are an afterthought.** Current speed exists only as a value buried in a
   data-box dropdown; a reviewer's specific complaint is having to re-select it every
   time because it can't be pinned. No current stations, no slack times, no transit
   planning. The "current-led, tide-paired" detail view has no competition here.
2. **Non-US accuracy is a real, reported problem.** UK reviewers report wrong times
   *and* wrong datums/depths ("by a margin that could pose navigation risks", south-coast
   double high waters). This is the spec's §1 wedge claim, now evidence-backed. Datum
   handling is exactly where they fall down — our datum labels + station provenance and
   CHS-correct Canadian data attack it directly.
3. **Data provenance is opaque.** "Best data providers in the world," unnamed (pattern
   matches WorldTides/Stormglass-style aggregators — same class our spec bars from core
   for TOS/caching reasons). No station provenance, no datum disclosure in-app. Our
   provenance-and-confidence story is the trust contrast.
4. **Online-first architecture.** Offline is partial (Watch complications cache; tables
   "faster when offline") but conditions come from live providers; no review praises
   offline use. Not a redundancy tool.
5. **Heft + battery.** 320 MB; always-on location noted in the listing's battery
   warning. An offline harmonic app can be a fraction of both.

## Operational complaints to design against

Slow initial load / black screens; Watch complication sync delays; station-search lag;
**no way to permanently pin a chosen metric on the main screen** (the currents
complaint generalizes — our current-led hero is the fix); a Watch units-rendering
glitch. None are fatal at 4.7★ — but they're the papercuts a smaller, offline app can
simply not have.

## What to steal for Phase 1

- **Chart interaction grammar**: press-hold to read a moment + swipe across days is the
  category-standard gesture set; our continuous scrubbable timeline already matches and
  exceeds it — keep snap targets, don't regress to day-paging.
- **Widget customization depth** as the north star for our (free) widgets — theirs win
  reviews because users compose exactly the data they want, not because of any single
  layout.
- **Scheduled Live Activities**: their pattern (auto-start at a chosen time) maps
  perfectly onto deterministic slack windows — backlog #1's "start the activity with
  the known slack time" is validated by the market leader shipping the same mechanic
  for sunsets.
- **Watch-offline-first complications** as the bar for our eventual Watch work.
- **Responsive-indie-developer identity** (hello@ address, fast fixes, praised in
  reviews) — same brand posture Sailing Naturali already has.

## What to explicitly not copy

- Paywalled widgets/complications (our differentiator is shipping them free).
- Weather-first breadth: their 12-condition weather bar is their moat and their server
  bill. Our §5 boundary (weather = paid live overlay, later) stays.
- Opaque data sourcing; aggregator dependency; 320 MB footprint; always-on location.

## Verdict for the spec

Benchmark confirmed, wedge confirmed, no spec changes required beyond marking this
teardown done. Phase 1 UI can proceed: match their interaction grammar on the chart,
beat them outright on currents, provenance, offline, and free widgets.
