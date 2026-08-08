# Online gates — the fit-rejects, backed by official CHS predictions

2026-08-08. Approved in brainstorm. Origin: a fresh-install report that Sechelt
Rapids (Skookumchuck) is unfindable in the app. It was a validated candidate,
deliberately excluded — the on-device harmonic fit misses CHS's published
slacks there by 15.5 min median / 39.5 min worst (`tools/gen-chs-gates.mjs`
rejects table). The absence was the right call; its invisibility was not.

## Decision

The 7 fit-reject gates (Beazley Passage, Dent Rapids, Gabriola Passage,
Juan de Fuca East, Sechelt Rapids, Second Narrows, Tillicum Bridge) become
**online gates**: findable everywhere, rendered from CHS's own published
prediction series fetched on demand, honest about why nothing exists offline.
The fetched window persists, so a dock-side fetch covers an offline transit.

Precision rationale: the rejects failed FITTING, not data availability — the
official predicted series the validator compared against is ground truth.
Online gates skip modelling entirely and render the published numbers.

## §1 Identity — they're just gates

- `tools/gen-chs-gates.mjs`: the rejects move from the comment block into
  emitted entries with `online: true`, carrying name/region/position/aliases
  from the station-corrections registry (Sechelt's "skookumchuck" alias must
  ship — search-by-alias is the origin bug) and the measured failure in
  plain-words form for the honesty card (see §3).
- `ChsCurrentGateInfo` gains `let online: Bool` (default false, absent in
  existing entries' json).
- They remain `StationItem.chsCurrent`: search, map pin, list cards,
  favorites, recents all inherit. Ids are bare registry keys — the
  `CurrentStationRecord.itemId` rule (fix/chs-favorite-ids) already covers
  them.
- They are NOT in the fit queue and never auto-fit; `ChsQueue`/`ChsFitService`
  must skip `online` entries.

## §2 Detail, fetched — the real thing

- `ChsDetailView`'s `.currentGate` case routes `online` gates to a
  fetch-backed detail instead of the fit-waiting page.
- Fetch: the official CHS predicted current series for the strip's full
  window (today −48h … +132h, the `Timeline` constants) via the same IWLS
  client the fitter uses. Persisted per-gate (a sibling store to
  `ChsModelStore`), replaced wholesale on refetch.
- Render the NORMAL single-track current detail from the fetched points:
  scrub strip, schedule, slack window, extreme labels — `TimelineData`
  already accepts point series. Slack/max events come from a small pure scan
  over the samples (zero crossings + local extrema), not the harmonic engine.
- No fast-answer/provisional machinery: these are exact published numbers.
- Provenance footer (the inverse of the fitted footer, same register):
  "CHS-published predictions · fetched <date>, covers to <date> — not
  computed on this device". Refetch on appear when connected and the window's
  remaining coverage is under half the strip's forward span.
- Set bearings: flood/ebb directions come from the registry entry like any
  gate (readout arrows and schedule arrows work unchanged).

## §3 Detail, unfetched or expired — the honesty card

- MapHeader (star works — the bare-id rule) + an honesty card in the CHS
  amber/plain register:
  - WHY offline is empty: "Slackwater's on-device model missed the published
    slacks here by up to ~40 minutes in testing, so it won't guess at
    <name>." (per-gate number from §1's emitted data)
  - WHAT connecting does: fetches CHS's official predictions.
  - A tappable nearest-shipped-gate link in the quiet-link convention
    (`TideAtPortLink`'s visual pattern; nearest by distance among the 11
    shipped `chsCurrent` gates — not derived gates, not other online gates).
- Auto-fetch on appear when connected; a manual fetch affordance when the
  auto attempt failed.
- Beyond the persisted window: same card, plus when the stale window exists,
  say what it covered ("fetched Aug 8 — covered to Aug 15").

## §4 Cards

- Fetched-and-current: the card reads like any gate (next slack from the
  cached window).
- Unfetched/expired: the pending-card `message` slot carries "Online —
  official CHS predictions, fetched when connected". No reading, no
  dead-looking blank.

## §5 What this retires / defers

- Sechelt-as-derived-gate (deferred item 1) is obsolete: official numbers
  beat a community-lag schematic.
- A real offline model for hydraulic stations (deferred item 2) stays
  deferred; the per-gate window store is the seam a future model slots into.

## §6 Tests

- Unit: the event-scan function (crossings, extrema, series edges, a
  slack-free monotone window); window-expiry/refetch-threshold logic; json
  decode of `online` entries (and that existing entries decode with
  `online == false`).
- UI (fast plan, no live network): search finds "sechelt" AND "skookumchuck";
  unfetched detail shows the honesty card, its nearest-gate link navigates,
  and the star round-trips to a Favorites group; fetched detail renders the
  strip and schedule from a canned/seeded series.
- Live (full plan only): one online gate end-to-end fetch against IWLS,
  asserting the provenance line carries real dates.

## Open item (verify during planning)

The IWLS current-prediction endpoint id mapping for the 7 rejects — the
validator resolved them once, so they should resolve; confirm before the
plan fixes the fetch design, and record each gate's IWLS id in the emitted
json like the shipped gates do.

## House rules

Branch-and-PR (`feature/online-gates` off main), never merge own PR;
spec → plan → subagent-driven execution; `./scripts/test.sh` green both
simulators; live-network coverage stays in the Full plan.
