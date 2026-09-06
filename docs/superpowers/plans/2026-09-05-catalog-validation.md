# Catalog Validation Implementation Plan

**Goal:** First implementation slice of PR #278: a throwing six-file reader and pure candidate validation, exercised against the shipped catalogs.

**Architecture:** `CatalogSnapshot` decodes the existing record types from a resource directory and validates identity, models, joins, and removals before exposing the candidate. Existing app/widget loading stays in place until the next slice supplies atomic storage and fallback; this PR does not close #234.

**Spec:** `docs/superpowers/specs/2026-09-05-catalog-refresh-design.md`

- [x] Add contextual lookup/read/decode/validation errors and a throwing catalog reader; no empty-array recovery.
- [x] Decode all six catalogs, validate identity, constituent structure, joins, removals and NOAA widget-scanner compatibility, and build merged records and indexes only after uniqueness checks.
- [x] Test the shipped bundle, malformed/missing/empty files, identity and model defects, broken joins, and tombstoned removals by mutating copies of the shipped files.
- [x] Compile app and widget, run the repository test script, and inspect results. Publish as a draft until a complete CI result is available.

Deferred to subsequent PRs: App Group persistence and fallback, runtime accessor migration, background transfer lifecycle, generation invalidation, cumulative generator changes, and Cloudflare publishing. No new dependencies or generated data changes.

Before remote activation, TideEngine must expose a public constituent-name lookup so the validator can reject unknown-only models. Its current public prediction API silently drops unknown names; duplicating its private catalog or probing predictions would give an unreliable validation rule. This slice validates nonempty names, finite phases and finite nonnegative amplitudes with at least one positive amplitude.

Verification: 21 focused catalog/widget-loader tests passed. The repository script passed all 330 unit tests; UI workers completed according to scheduling logs, but Xcode hung finalizing its result bundle and was stopped. A finalized full-suite result remains required before marking the PR ready.
