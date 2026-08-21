# Docs

Two kinds of documents live here, split by shelf life:

**Living docs** (root) — kept current; when reality changes, these change:

| Doc | What |
|---|---|
| [`product-landscape.md`](product-landscape.md) | The full stack — every product, the four layers, how they connect, rollout order (M1–M6). Start here |
| [`chs-data-model.md`](chs-data-model.md) | What Canada gives us and what it doesn't — IWLS series, the licensing posture that shapes the architecture, the four tiers of current coverage, what "validated" means, why there is no current field. Standalone: read it before scoping anything touching Canadian coverage |
| [`gtm.md`](gtm.md) | Slackwater go-to-market — channels ranked by leverage, drafted assets. Private; nothing in it goes in public posts |

**Research snapshots** ([`research/`](research/)) — dated, point-in-time; superseded by newer
snapshots rather than edited:

| Doc | What |
|---|---|
| [`market-research-2026-07-17.md`](research/market-research-2026-07-17.md) | The tides/currents app landscape — competitor table, the currents gap, pricing anchors, spec gap-analysis |
| [`tide-guide-teardown-2026-07-17.md`](research/tide-guide-teardown-2026-07-17.md) | Design-benchmark teardown of Tide Guide (the ADA winner) — what to steal, what to flank |
| [`design-readiness-2026-07-22.md`](research/design-readiness-2026-07-22.md) | Pre-build design review — verdict: ready; loose ends listed blocking → parked |
| [`mytide-2026-08-21.md`](research/mytide-2026-08-21.md) | MyTide.ie — Irish indie tide PWA, convergent design; gauge-vs-modelled overlay + crossing windows worth stealing |

Deeper background (specs, superpowers plans) lives in the Slackwater planning repo
(`sailingnaturali/slackwater`, private) — ask if you want anything from there surfaced here.

**One spec there is cited from this repo by bare name and is worth naming here**, because four
files reference it and none of them says where it is:

| Cited as | Lives at | What it settles |
|---|---|---|
| `chs-online-design` | `sailingnaturali/slackwater` → `docs/superpowers/specs/2026-07-21-chs-online-design.md` | **§2 is the CHS licence architecture** — why Canadian predictions are *fetched per user* and never bundled (clause 3 bars redistribution, clause 10 permits the user's own derivation; we ship a client, so nothing is redistributed). **§6a** is where the ±20-min maxima bar comes from |

Cited by `Slackwater/ChsStation.swift:6`, `tools/gen-chs-stations.mjs:5`,
`tools/FitValidation/Sources/fit-validation/main.swift:114`, and
`spikes/chs-currents-fit/README.md:32`. Read §2 before changing anything about what CHS data
this app stores, ships, or re-serves — see #99 for what happens when that architecture is
mistaken for a loophole that generalises to other datasets (it does not; it works only because
DFO runs IWLS as a service the device can query directly).

**That argument is now reproduced in [`chs-data-model.md`](chs-data-model.md) §3**, in full and
with the three-option table, so it can be read without access to the private repo — which is
the point of the row above it. A pointer resolves a citation; it does not let most readers
follow the reasoning. Reasoning that work in *this* repo depends on should not live only
there, and `chs-data-model.md` is the pattern to follow.
