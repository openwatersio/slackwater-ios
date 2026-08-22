# RUN method certification (spec §6a)

Verdict of record for the two committed passes, graded against live NOAA CO-OPS
predictions with `tools/FitValidation` — the M47 bars, unmodified, file-input mode.
Methodology: `certify_patch.py` samples = the anchor's own 190-day `currents_predictions`
series (6-min, signed `Velocity_Major`) scaled by `scale(check station's nearest section)`;
events = the check station's own published `MAX_SLACK` truth over a 7-day held-out window
28 days past the fit end. `run_certify.sh` runs one `fit-validation` pass per pair; the
tool's own exit code (captured in `data/verdicts/*.status`) is the verdict of record, not
a re-derivation here.

**Bars** (`main.swift:161-167`): `slackMedianMin <= 15.0`, `slackMaxMin <= 30.0`,
`extremaMedianMin <= 20.0`, `speedMedianKn <= 0.5`, `slackUnmatched == 0`, wrong-sign
extrema `< 60%` of scored. All four must hold on the `210d` window for PASS; the `60d`
window is printed but does not gate.

## Verdict: 1 of 4 PASS — gate does not clear

Per Step 4 of the task brief: any FAIL stops the phase here. Tasks 5-9 do not start.
The spec §7 composite Discovery-FVCOM path — not a loosened bar — is the fallback, and
which stations (if any) get re-scoped (spec §9's "terminate west of Yokeko" note) is an
owner decision, not something applied here.

| check station | pass | verdict | dist. from anchor | applied scale | slack med/max (min) | extrema med/max (min) | speed med/max (kn) | rms (kn) |
|---|---|---|---|---|---|---|---|---|
| tacoma-narrows-PUG1524 | Tacoma Narrows | **FAIL** | 3.55 km | 0.5393 | 17.7 / 49.2 | 19.3 / 82.5 | 0.63 / 1.14 | 0.10 |
| tacoma-narrows-PUG1526 | Tacoma Narrows | **FAIL** | 3.42 km | 0.5490 | 57.5 / 174.1 | 26.7 / 85.4 | 0.85 / 1.44 | 0.10 |
| tacoma-narrows-PUG1528 | Tacoma Narrows | PASS | 1.75 km | 0.9064 | 10.4 / 29.9 | 14.1 / 54.5 | 0.32 / 0.65 | 0.17 |
| deception-pass-PUG1629 | Deception Pass | **FAIL** | 2.33 km | 0.4883 | 8.1 / 34.8 | 14.5 / 103.6 | 0.26 / 0.84 | 0.19 |

All four: `slackUnmatched` 0 except PUG1526 (2 unmatched), wrong-sign 0/N throughout (no
flood/ebb axis flips anywhere).

## Per-station detail

### tacoma-narrows-PUG1524 — FAIL

Anchor PUG1527 (47.27432, -122.54532); check station 47.306, -122.55003; nearest section
index 2 of `kept_range` [0, 46], 294 m from that section's center, 3545 m from the anchor
itself; applied scale 0.5393.

| metric | value | bar | within bar? |
|---|---|---|---|
| slack median | 17.7 min | <= 15.0 | **no** |
| slack max | 49.2 min | <= 30.0 | **no** |
| slack matched/unmatched | 31/0 | unmatched == 0 | yes |
| extrema median | 19.3 min | <= 20.0 | yes |
| extrema max | 82.5 min | (not gated) | - |
| extrema scored/total | 29/31 | - | - |
| speed median | 0.63 kn | <= 0.5 | **no** |
| speed max | 1.14 kn | (not gated) | - |
| wrong-sign | 0/31 | < 60% | yes |

Fails on slack median, slack max, and speed median.

### tacoma-narrows-PUG1526 — FAIL

Anchor PUG1527; check station 47.304, -122.55675; nearest section index 3, 214 m from
that section's center, 3415 m from the anchor; applied scale 0.5490.

| metric | value | bar | within bar? |
|---|---|---|---|
| slack median | 57.5 min | <= 15.0 | **no** |
| slack max | 174.1 min | <= 30.0 | **no** |
| slack matched/unmatched | 28/2 | unmatched == 0 | **no** |
| extrema median | 26.7 min | <= 20.0 | **no** |
| extrema max | 85.4 min | (not gated) | - |
| extrema scored/total | 22/31 | - | - |
| speed median | 0.85 kn | <= 0.5 | **no** |
| speed max | 1.44 kn | (not gated) | - |
| wrong-sign | 0/31 | < 60% | yes |

The worst of the four — fails every gated bar. This is the check station furthest from
the anchor by scale (0.549, i.e. roughly half the anchor's cross-section area) and second
furthest by distance (3.42 km).

### tacoma-narrows-PUG1528 — PASS

Anchor PUG1527; check station 47.2613, -122.55828; nearest section index 43, 80 m from
that section's center, 1749 m from the anchor; applied scale 0.9064.

| metric | value | bar | within bar? |
|---|---|---|---|
| slack median | 10.4 min | <= 15.0 | yes |
| slack max | 29.9 min | <= 30.0 | yes (0.1 min to spare) |
| slack matched/unmatched | 31/0 | unmatched == 0 | yes |
| extrema median | 14.1 min | <= 20.0 | yes |
| extrema max | 54.5 min | (not gated) | - |
| extrema scored/total | 31/31 | - | - |
| speed median | 0.32 kn | <= 0.5 | yes |
| speed max | 0.65 kn | (not gated) | - |
| wrong-sign | 0/31 | < 60% | yes |

Closest check station to the anchor by distance and by scale (0.906, near unity) —
also the only one that clears every bar, and the slack-max bar clears by only 0.1 min.

### deception-pass-PUG1629 — FAIL

Anchor PUG1701 (48.40619, -122.64312); check station 48.41272, -122.61317; nearest section
index 37 of `kept_range` [0, ..], 58 m from that section's center, 2330 m from the anchor;
applied scale 0.4883.

| metric | value | bar | within bar? |
|---|---|---|---|
| slack median | 8.1 min | <= 15.0 | yes |
| slack max | 34.8 min | <= 30.0 | **no** |
| slack matched/unmatched | 31/0 | unmatched == 0 | yes |
| extrema median | 14.5 min | <= 20.0 | yes |
| extrema max | 103.6 min | (not gated) | - |
| extrema scored/total | 31/31 | - | - |
| speed median | 0.26 kn | <= 0.5 | yes |
| speed max | 0.84 kn | (not gated) | - |
| wrong-sign | 0/31 | < 60% | yes |

Fails on a single bar — slack max (worst-case single-event timing error), 34.8 min against
a 30.0 min ceiling. Every other metric, including slack median, clears comfortably. This
is the only station of the three failures that misses on one bar rather than several.

## Reading across the two passes

- **Tacoma Narrows**: 1 of 3 check stations pass. The pass (PUG1528) sits 1.75 km from the
  anchor with scale 0.906 (near-unity continuity scaling). Both failures (PUG1524, PUG1526)
  sit roughly 3.4-3.5 km away at scale ~0.54 — the anchor's own series, halved by
  continuity scaling, no longer tracks those stations' timing or amplitude closely enough.
  PUG1526 is the outlier even within that pair, failing every gated bar plus 2 slack events
  that never matched within the 180-minute window.
- **Deception Pass**: the only check station (PUG1629, 2.33 km, scale 0.488) fails on one
  bar only — slack max — with every other metric passing comfortably, including slack
  median at roughly half the ceiling.
- No station on either pass shows a reversed flood/ebb axis (wrong-sign is 0/N everywhere).

## Harness notes

No pipeline code changes were needed to run this gate. `certify_patch.py` fetched all four
190-day anchor-scaled sample sets and 7-day held-out truth-event sets from the live NOAA
CO-OPS API on the first attempt (resumable via the `data/certify/samples|events` file
check, not exercised this run). `run_certify.sh` built and ran `tools/FitValidation`
against all four pairs cleanly; report files landed at
`/tmp/fit-validation/reports/<label>-210d-report.json` and were copied to
`data/verdicts/<label>.json` as the script expects.

Run window: fit end ~2026-08-21 (190 days back to ~2026-02-12), held-out validation window
2026-09-19 to 2026-09-26 (28 days past fit end, 7 days long) — both passes.
