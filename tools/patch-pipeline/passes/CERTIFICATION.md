# RUN method certification (spec §6a, amended protocol)

Verdict of record for the two committed passes, graded against live NOAA CO-OPS
predictions with `tools/FitValidation` — the M47 bars, unmodified, file-input mode.
`run_certify.sh` runs one `fit-validation` pass per pair; the tool's own exit code
(captured in `data/verdicts/*.status`) is the verdict, not a re-derivation here.

**Bars** (`main.swift:161-167`): `slackMedianMin <= 15.0`, `slackMaxMin <= 30.0`,
`extremaMedianMin <= 20.0`, `speedMedianKn <= 0.5`, `slackUnmatched == 0`, wrong-sign
extrema `< 60%` of scored. All must hold on the `210d` window; `60d` is printed,
non-gating. Nothing here is loosened — this run changed *which stations are graded*,
by the objective bounds rule of §3, and not one bar.

**What is graded, after the owner ruling of 2026-08-21.** §3 terminates a patch at the
first section wider than **1.3 × the throat**. Applying that rule (`sections.py`, this
run) leaves Tacoma at `kept_range [18, 46]` of `[0, 46]` and Deception at `[11, 14]` of
`[0, 40]`. Three of the four first-run check stations fall outside those bounds and
become **reference rows** — recorded, not gating. The gating in-bounds pair is:

1. **PUG1528 predicted from the PUG1527 anchor** — the anchor's own 190-day
   `currents_predictions` series (6-min, signed `Velocity_Major`) × `scale` at
   PUG1528's section, graded against PUG1528's published `MAX_SLACK` truth.
2. **The reciprocal — PUG1527 predicted from a PUG1528 anchor** — same geometry,
   scales renormalized so the PUG1528 section is 1.0 (`scales[31]/scales[43]` =
   1.0/0.9064 = **1.1033**), graded against PUG1527's own truth.

Held-out window 2026-09-19..2026-09-26 (28 days past the 190-day fit end), both pairs.

## Verdict: 1 of 2 in-bounds checks PASS — the gate does not clear

| gating check | verdict | series anchor | scale | dist. | slack med/max (min) | extrema med/max (min) | speed med/max (kn) | rms (kn) |
|---|---|---|---|---|---|---|---|---|
| `tacoma-narrows-PUG1528` | **PASS** | PUG1527 | 0.9064 | 1.75 km | 10.4 / 29.9 | 14.1 / 54.5 | 0.32 / 0.65 | 0.17 |
| `tacoma-narrows-recip-PUG1527` | **FAIL** | PUG1528 | 1.1033 | 1.75 km | **20.3 / 52.2** | **25.4** / 65.2 | 0.20 / 0.54 | 0.24 |

Both: 31 slack events matched, 0 unmatched; 31/31 extrema scored; wrong-sign 0/31 (no
flood/ebb axis flip in either direction).

### `tacoma-narrows-PUG1528` — PASS

Anchor PUG1527 (47.27432, -122.54532, section 31); check station 47.26130, -122.55828,
section 43 (80 m from its centre, 1749 m from the anchor), width 1660 m — inside
`kept_range [18, 46]`.

| metric | value | bar | within bar? |
|---|---|---|---|
| slack median | 10.4 min | <= 15.0 | yes |
| slack max | 29.9 min | <= 30.0 | yes (0.1 min to spare) |
| slack matched/unmatched | 31/0 | unmatched == 0 | yes |
| extrema median | 14.1 min | <= 20.0 | yes |
| extrema max | 54.5 min | (not gated) | - |
| speed median | 0.32 kn | <= 0.5 | yes |
| speed max | 0.65 kn | (not gated) | - |
| wrong-sign | 0/31 | < 60% | yes |

Unchanged from the first run — same station, same section, same applied scale (0.9064).
The new bounds neither added nor removed anything from this pair; it is the same
measurement, reported twice.

### `tacoma-narrows-recip-PUG1527` — FAIL

Series anchor PUG1528 (section 43), target PUG1527 (section 31, 195 m from its centre),
renormalized scale 1.1033. Both sections are inside `kept_range [18, 46]`.

| metric | value | bar | within bar? |
|---|---|---|---|
| slack median | 20.3 min | <= 15.0 | **no** |
| slack max | 52.2 min | <= 30.0 | **no** |
| slack matched/unmatched | 31/0 | unmatched == 0 | yes |
| extrema median | 25.4 min | <= 20.0 | **no** |
| extrema max | 65.2 min | (not gated) | - |
| speed median | 0.20 kn | <= 0.5 | yes |
| speed max | 0.54 kn | (not gated) | - |
| wrong-sign | 0/31 | < 60% | yes |

Fails the three timing bars; **both amplitude bars pass comfortably** — the renormalized
continuity scale reproduces PUG1527's speeds from PUG1528's series to a 0.20 kn median,
*better* than the forward direction's 0.32 kn.

**The asymmetry is the finding.** The same 1.75 km of channel, graded both ways, gives
10.4 min and 20.3 min slack-median error. Timing error decomposes as
`fit(A) − truth(B) = [fit(A) − truth(A)] + [truth(A) − truth(B)]`: the second term flips
sign when the direction reverses, the first does not. A forward pass and a reciprocal
fail is what that looks like when the two terms happen to cancel one way and add the
other — i.e. the forward PASS is not, on its own, evidence that uniform phase holds
between these two stations. Two gradings of one geometry were exactly the point of the
amended protocol, and they disagree. The physics claim under test (§3: uniform anchor
phase along the patch, the L ≪ λ/4 criterion) is not supported by this pair; amplitude
continuity (`|u| = |u|_gate · A_gate/A(x)`) is, in both directions.

Per §6a: **fail → the phase halts**, and the fallback conversation is the composite §7
Discovery-FVCOM path — not a loosened bar. No further protocol edits were made here.

## Reference rows — out of bounds, non-gating

First-run numbers (commit `7ebd4be`), retained as the empirical case for §3's bounds
rule. These stations lie outside the flare-terminated `kept_range`, so under the amended
protocol the patch makes no claim about them and they do not gate. They are listed
because *why* they fail is the argument for the rule.

| station | pass | section (width) | inside bounds? | slack med/max (min) | extrema med (min) | speed med (kn) | first-run verdict |
|---|---|---|---|---|---|---|---|
| PUG1524 | Tacoma | 2 (2180 m) | no — `[18, 46]` | 17.7 / 49.2 | 19.3 | 0.63 | FAIL |
| PUG1526 | Tacoma | 3 (2090 m) | no — `[18, 46]` | 57.5 / 174.1 | 26.7 | 0.85 | FAIL |
| PUG1629 (Yokeko) | Deception | 37 (490 m) | no — `[11, 14]` | 8.1 / 34.8 | 14.5 | 0.26 | FAIL (slack max only) |
| PUG1628 (Skagit Bay) | Deception | — | far field | not fetched | — | — | — |

**Bounds rationale (§3).** Tacoma's throat is the anchor section at 1370 m; the limit is
1.3 × 1370 = **1781 m**. Walking north from section 31 the width crosses it at section 17
(1790 m), so the patch ends at 18; walking south nothing exceeds it, so it ends at 46.
PUG1524 and PUG1526 sit at sections 2-3 where the channel has opened to 2180 and 2090 m —
1.6× the throat, in the Point Defiance mouth flare, 2.1-2.3 km beyond the nearest kept
section. Their first-run numbers (PUG1526 failing *every* gated bar, with 2 slack events
never matching inside a 180-minute window) are what the confined-channel assumption
looks like after the walls end.

Deception's throat is 140 m at the anchor (limit **182 m**); the width jumps to 350 m at
section 10 and 550 m at section 15, so `kept_range` is `[11, 14]` — a 300 m strip through
the pass itself. Yokeko is 2.2 km east at section 37, in the 490 m wide eastern arm.
Its single-bar first-run miss (slack max 34.8 vs 30.0 min) is spec §9's predicted phase
non-uniformity along that arm, realized. **Deception now has no in-bounds check station
and does not gate** — the objective rule shrank it past its only candidate.

PUG1628 (Skagit Bay channel, 48.39783, -122.57955) was never fetched, in this run or the
first; the far-field row stays empty rather than being filled from a re-run.

## Harness notes

`sections.py` gained the flare truncation (`FLARE = 1.3`, per-pass `flare_ratio`
override, throat reference recorded in each pass doc); `certify_patch.py` gained
`reciprocal_spec` + `nearest_section`. Both are covered by unit tests
(`test_sections.py::test_kept_range_stops_at_the_flare`,
`test_certify.py::test_reciprocal_*`). Regenerating the passes changed **only**
`kept_range` and the two new keys — every section centre, width and area is byte-identical
to the first run, so nothing in these numbers moved because the geometry moved.

The first run's verdict files are preserved at `data/verdicts-run1/` (gitignored, like
all of `data/`); this run's are at `data/verdicts/`.
