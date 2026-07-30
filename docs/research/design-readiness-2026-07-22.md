# Slackwater iOS — design readiness review

*2026-07-22. Full-spec sweep ahead of the iOS build.*

**Verdict: the design is ready to build.** Phase 0 (accuracy-before-UI) is done and
validated — `slackwater-engine` shipped (Friday Harbor 7.9 min / 3.5 cm vs NOAA; Salish
pass currents validated; CHS licensing moot by design), web client live at
slackwater.sailingnaturali.com. Spec supersessions are cleanly cross-referenced; nothing
is scattered or contradictory. *(Update 2026-07-30: the iOS app repo now exists — this one,
`openwatersio/slackwater-ios` — created docs-first; the SwiftUI app lands here. Specs
referenced below live in the Slackwater planning repo's `docs/superpowers/specs/`.)*

## The prototype-visibility problem (fix first)

The specs treat the Claude Design project **"Tides and Currents"** (component `TidesApp`,
variants `a`/`b`, plus the FTUE component) as the source of truth for many settled
decisions — but it is **not readable from Claude Code by any model, ever**. DesignSync
only lists writable *design-system* projects; the only one is "Sailing Naturali"
(charter-site web components). "Tides and Currents" is a regular claude.ai
project/artifact, so every agent session hits the same wall. This is why prior sessions
"got confused."

**Fix: export the prototype code into this repo** (`prototype/` — now meaning
`slackwater-ios`, where the app lives). Loose ends 1–3 below all require reconciling spec
against prototype. (Alternative — recreate it as a design-system project — is more setup
for a worse fit; a prototype isn't a component library.)

## Loose ends (each recorded once, in the right spec — consolidated here)

Blocking / near-term for the iOS build:

1. **Current→tide station pairing field doesn't exist.** The paired detail chart needs a
   data-layer association (detail-view spec §2, §9); the registry has no such field
   (chs-online spec §5c — web ships current-only as the fallback). Registry work in
   `station-corrections`; gates the paired view.
2. **Readout legibility over the live map.** Hero readout over a moving particle field
   over Seascape's *light* chart style vs our dark UI — "real and immediate" risk
   (map-hero spec §5a, §7). Scrim or dark restyle; prototype before assuming.
3. **Land basemap substrate unresolved.** Seascape is not a land layer (its style borrows
   OSM raster, forbidden for apps). OSM extract as PMTiles vs `openwatersio/seamap` —
   undecided (map-hero spec §5a).

Parked deliberately:

4. **Tide-only station map animation** — no set bearing → particles meaningless; Bryan is
   thinking about the treatment (map-hero §7).
5. **Confidence "fog of war" rendering** — unsolved by design; don't flatten back into a
   badge (detail-view §6).
6. **Per-station slack-limit override UI** — how the delta is set without a second
   settings surface (detail-view §5, §9).

Small / later:

7. Station-corrections: gazetteer source for PNW places; whether current stations share
   the naming namespace (station-corrections spec §7).
8. CHS-online: unfetched-station presentation in search/Nearby (§10); offline-region
   download UX (unscoped by design, map-hero §7); Slackwater↔Sailing Naturali brand depth
   (app spec §7, open since the first spec).
