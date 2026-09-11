# Docs

Two kinds of documents live here, split by shelf life:

**Living docs** (root) — kept current; when reality changes, these change:

| Doc | What |
|---|---|
| [`chs-data-model.md`](chs-data-model.md) | What Canada gives us and what it doesn't — IWLS series, the licensing posture that shapes the architecture, the four tiers of current coverage, what "validated" means, why there is no current field. Standalone: read it before scoping anything touching Canadian coverage |

**Research snapshots** ([`research/`](research/)) — dated, point-in-time; superseded by newer
snapshots rather than edited:

| Doc | What |
|---|---|
| [`design-readiness-2026-07-22.md`](research/design-readiness-2026-07-22.md) | Pre-build design review — verdict: ready; loose ends listed blocking → parked |
| [`european-currents-licensing-2026-08-16.md`](research/european-currents-licensing-2026-08-16.md) | Whether European current data can be bundled or fetched, authority by authority |

Strategy, market and competitor research, the App Store listing text, the comparison-page plan and the product landscape are private and live in the [Open Waters planning repo](https://github.com/openwatersio/planning/tree/main/slackwater-ios). Technical reasoning needed to work on this app lives here; read [the CHS data model](chs-data-model.md#3-the-licence-architecture--the-load-bearing-section) before changing how Canadian data is stored, bundled or served.

## Archived source citations

Bare `chs-online-design` citations in `Slackwater/ChsStation.swift`, `tools/gen-chs-stations.mjs`, and `tools/FitValidation/Sources/fit-validation/main.swift` resolve to the following source. The current licence architecture is documented in `chs-data-model.md` §3.

| Citation | Source | Subject |
| --- | --- | --- |
| `chs-online-design` §2 | [Archived CHS online design](https://github.com/sailingnaturali/slackwater/blob/51648731c02addef265f4839c9632145be962ad0/docs/superpowers/specs/2026-07-21-chs-online-design.md#2-the-licence-architecture) | The per-user fetch and local-storage rationale |
| `chs-online-design` §6a | [Archived current-station selection rule](https://github.com/sailingnaturali/slackwater/blob/51648731c02addef265f4839c9632145be962ad0/docs/superpowers/specs/2026-07-21-chs-online-design.md#6a-currents-the-rule-already-in-the-data) | Which current stations belong in the registry; this section does not specify a maxima-timing tolerance |

The fit spike's numerical acceptance criteria are in its own [threshold table](../spikes/chs-currents-fit/README.md#the-bar-set-before-scoring).
