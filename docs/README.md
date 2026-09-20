# Documentation

Documentation here describes the current product, maintained operating procedures, and evidence needed to trust its predictions. Update the relevant document with the implementation. Completed plans, session reports, screenshots used only for review, and superseded prototypes belong in Git history or pull requests.

## Product and data contracts

| Document | Purpose |
|---|---|
| [Scrubber](scrubber.md) | Detail timeline behavior, rendering, input, accessibility, and platform conformance |
| [Current charts](current-charts.md) | Current, slack-window, magnitude, and direction semantics; the scrubber spec owns detail presentation |
| [CHS data model](chs-data-model.md) | Canadian coverage, local fitting, validation, and data-use boundaries |
| [App Store metadata](appstore-metadata.md) | Listing copy, privacy answers, and accessibility declarations |
| [Licensing](licensing.md) | App licensing and the contributor agreement |

## Operating procedures and evidence

| Document | Purpose |
|---|---|
| [TestFlight](testflight.md) | Release setup and signing |
| [Release notes](release-notes/) | Versioned release copy consumed by `scripts/testflight.sh`; retained release history |
| [CHS current validation](validation/chs-currents.md) | Fit acceptance bars, recorded measurements, and reproduction |
| [World tide validation](validation/world-tide-stations.md) | Datum/amplitude validation evidence and its timing limitation |
| [Generated resources](../Slackwater/Resources/README.md) | Bundle inputs, generation order, and provenance |
| [Fill pipeline](../tools/fill-pipeline/README.md) | SSCOFS speed-fill certification, fitting, and packing |
| [SSCOFS validation](../tools/sscofs-validation/README.md) | Reusable validation tools imported by the fill pipeline |
| [Patch pipeline](../tools/patch-pipeline/README.md) | Bathymetry, bounded current patches, and certification evidence |
| [Feedback intake](../services/testflight-feedback/README.md) | Private TestFlight feedback setup, storage, and recovery |

## Project structure

`Slackwater/` contains the app, `SlackwaterWidgets/` the extension, and `SlackwaterTests/` and `SlackwaterUITests/` their checks. `project.yml` defines the generated Xcode project. `scripts/` holds build, test, and release entry points; `tools/` holds data generators and maintained validation pipelines. Service-specific code and docs live together under `services/`.

Use [CONTRIBUTING.md](../CONTRIBUTING.md) for workflow and [CLAUDE.md](../CLAUDE.md) for agent constraints. Temporary plans and experimental output go in ignored `.superpowers/` or `/tmp`. Preserve a reusable experiment as a named tool with a runbook and checks; preserve its lasting decision in the relevant product or data document.

Strategy, market research, and future product planning live in the private [planning repository](https://github.com/openwatersio/planning/tree/main/slackwater-ios). Reviewed proposals remain available in their PRs: [download tiers #453](https://github.com/openwatersio/slackwater-ios/pull/453), [catalog delivery #297](https://github.com/openwatersio/slackwater-ios/pull/297), and [alerts #371](https://github.com/openwatersio/slackwater-ios/pull/371). A merged design proposal alone does not mean its behavior ships.

## Archived source citations

Bare `chs-online-design` citations in `Slackwater/ChsStation.swift`, `tools/gen-chs-stations.mjs`, and `tools/FitValidation/Sources/fit-validation/main.swift` resolve to the following source. The current licence architecture is documented in `chs-data-model.md` §3.

| Citation | Source | Subject |
| --- | --- | --- |
| `chs-online-design` §2 | [Archived CHS online design](https://github.com/sailingnaturali/slackwater/blob/51648731c02addef265f4839c9632145be962ad0/docs/superpowers/specs/2026-07-21-chs-online-design.md#2-the-licence-architecture) | The per-user fetch and local-storage rationale |
| `chs-online-design` §6a | [Archived current-station selection rule](https://github.com/sailingnaturali/slackwater/blob/51648731c02addef265f4839c9632145be962ad0/docs/superpowers/specs/2026-07-21-chs-online-design.md#6a-currents-the-rule-already-in-the-data) | Which current stations belong in the registry; this section does not specify a maxima-timing tolerance |

The current-fit acceptance criteria and measurements are in [CHS current validation](validation/chs-currents.md).
