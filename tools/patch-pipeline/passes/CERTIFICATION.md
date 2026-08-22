# RUN method certification (spec §6a, second amendment)

Verdict of record for the two committed passes, graded against live NOAA CO-OPS
predictions with `tools/FitValidation` — the same tooling as the fill matrix, file-input
mode, one implementation of the rule, never a fork. `run_certify.sh` runs one
`fit-validation` pass per pair; the reports in `data/verdicts/*.json` are the numbers
below.

**Which bar gates, and which does not.** Owner ruling 2026-08-21 (spec §3 "Phase", §6a):
a patch is a **speed + direction field** and makes **no timing claim** — slack and
transitability authority stays with the gate card alone. So method certification gates on
the fill's **§4a speed-only bar: `speedMedianKn <= 0.5`** at every in-bounds check.
FitValidation still measures and prints the M47 timing bars (`slackMedianMin <= 15.0`,
`slackMaxMin <= 30.0`, `extremaMedianMin <= 20.0`) and its own exit code still folds them
in — **that exit code is not the gate here.** Those timing rows are recorded verbatim
below as the documented phase caveat. Nothing was loosened to make this land: the speed
bar is the fill's shipped bar, unchanged, and the timing numbers are published rather than
discarded.

**What is graded.** §3 terminates a patch at the first section wider than 1.3 × the
throat, which leaves Tacoma at `kept_range [18, 46]` of `[0, 46]` and Deception at
`[11, 14]` of `[0, 40]`. Three of the four first-run check stations fall outside those
bounds and become reference rows (below), not gates. The in-bounds pair is:

1. **PUG1528 predicted from the PUG1527 anchor** — the anchor's own 190-day
   `currents_predictions` series (6-min, signed `Velocity_Major`) × `scale` at PUG1528's
   section (0.9064), graded against PUG1528's published `MAX_SLACK` truth.
2. **The reciprocal — PUG1527 predicted from a PUG1528 anchor** — same geometry, scales
   renormalized so the PUG1528 section is 1.0 (`scales[31]/scales[43]` = 1.0/0.9064 =
   **1.1033**), graded against PUG1527's own truth.

Held-out window 2026-09-19..2026-09-26 (28 days past the 190-day fit end), both pairs.

## Gate: CLEARED — 2 of 2 in-bounds checks PASS on the §4a speed bar

Graded against **`speedMedianKn <= 0.5`** (spec §6a, the fill's §4a bar). Nothing in this
table is a timing measurement.

| in-bounds check | series anchor | scale | dist. | **speed median (kn)** | bar | **verdict** | speed max (kn) | rms (kn) | wrong-sign |
|---|---|---|---|---|---|---|---|---|---|
| `tacoma-narrows-PUG1528` | PUG1527 | 0.9064 | 1.75 km | **0.32** | <= 0.5 | **PASS** | 0.65 | 0.17 | 0/31 |
| `tacoma-narrows-recip-PUG1527` | PUG1528 | 1.1033 | 1.75 km | **0.20** | <= 0.5 | **PASS** | 0.54 | 0.24 | 0/31 |

Both directions clear with wide margin — 36 % and 59 % of the bar — and neither shows a
flood/ebb axis flip (wrong-sign 0/31 on both). **The short-channel continuity law
`|u|(x) = |u|_gate · A_gate/A(x)` is what these two rows certify**, in both directions
across the same 1.75 km of confined channel.

Deception Pass generates no in-bounds pair: the flare rule shrinks it to a 300 m strip
(`[11, 14]`) and its only candidate station, Yokeko PUG1629, is 2.2 km east of that.
It does not gate; it is covered by the Tacoma certification, which is what a
method-certification channel is for.

## Phase caveat (measured, not gating)

**These numbers are not a gate and were never presented as one under the current spec.**
They are the measured error of the §3 approximation "the anchor's phase everywhere",
recorded because a patch's streaks reverse on the anchor's slack and a user deserves to
know by how much that can differ from the water in front of them. Graded against the M47
timing bars (`slackMedianMin <= 15.0`, `slackMaxMin <= 30.0`, `extremaMedianMin <= 20.0`)
purely to put a number on it. Timing/transitability authority stays with the gate card
(spec §3, §6a).

### Run 2 — in-bounds pair, both directions of the same 1.75 km reach

| pair | slack med/max (min) | extrema med/max (min) | vs M47 timing bars | slack matched/unmatched |
|---|---|---|---|---|
| `tacoma-narrows-PUG1528` (fwd, PUG1527 → PUG1528) | 10.4 / 29.9 | 14.1 / 54.5 | within all three | 31 / 0 |
| `tacoma-narrows-recip-PUG1527` (rev, PUG1528 → PUG1527) | 20.3 / 52.2 | 25.4 / 65.2 | **outside all three** | 31 / 0 |

**The reciprocal is the finding.** Grading the same geometry both ways gives 10.4 min one
direction and 20.3 min the other. Timing error decomposes as
`fit(A) − truth(B) = [fit(A) − truth(A)] + [truth(A) − truth(B)]`; only the second term
flips sign on reversal, so a forward pass with a reciprocal fail is the signature of two
error terms cancelling one way and adding the other — meaning the forward direction's
clean timing was partly cancellation, not evidence that phase is uniform along the
channel. **Phase uniformity does not hold at gate grade here; the speed law does.** That
asymmetry is precisely what the owner ruling of 2026-08-21 acted on — see spec §3
("Phase") and §6a for the ruling and its rationale. Working figure for the caveat:
**~10–25 min median slack offset, worst case ~50 min**, over 1.75 km of confined channel —
the same ~±25 min class already documented for the fill backdrop.

### Run 1 — first-run timing rows, for the record

Same measurements from the first certification run (commit `7ebd4be`), when the
then-current protocol gated on M47 timing and the run returned 1/4. Retained verbatim so
the ruling's evidence base stays visible. `tacoma-narrows-PUG1528` is the same
measurement as run 2's forward row (same station, same section, same applied scale) —
identical numbers, reported twice.

| station | pass | slack med/max (min) | extrema med/max (min) | speed med/max (kn) | in bounds today? |
|---|---|---|---|---|---|
| PUG1528 | Tacoma | 10.4 / 29.9 | 14.1 / 54.5 | 0.32 / 0.65 | yes |
| PUG1524 | Tacoma | 17.7 / 49.2 | 19.3 / 82.5 | 0.63 / 1.14 | no |
| PUG1526 | Tacoma | 57.5 / 174.1 | 26.7 / 85.4 | 0.85 / 1.44 | no |
| PUG1629 (Yokeko) | Deception | 8.1 / 34.8 | 14.5 / 103.6 | 0.26 / 0.84 | no |

## Reference rows — out of bounds, non-gating

First-run numbers (commit `7ebd4be`), retained as the empirical case for §3's bounds rule.
These stations lie outside the flare-terminated `kept_range`, so the patch makes no claim
about them at all — neither speed nor timing — and they gate nothing. They are listed
because *why* they fail is the argument for the rule. Graded, at the time, against the
M47 bars.

| station | pass | section (width) | inside bounds? | slack med/max (min) | extrema med (min) | speed med (kn) | first-run verdict |
|---|---|---|---|---|---|---|---|
| PUG1524 | Tacoma | 2 (2180 m) | no — `[18, 46]` | 17.7 / 49.2 | 19.3 | 0.63 | FAIL |
| PUG1526 | Tacoma | 3 (2090 m) | no — `[18, 46]` | 57.5 / 174.1 | 26.7 | 0.85 | FAIL |
| PUG1629 (Yokeko) | Deception | 37 (490 m) | no — `[11, 14]` | 8.1 / 34.8 | 14.5 | 0.26 | FAIL (slack max only) |
| PUG1628 (Skagit Bay) | Deception | — | far field | not fetched | — | — | — |

Note that both out-of-bounds Tacoma stations also miss the **speed** bar (0.63 and
0.85 kn vs 0.5) — the bounds rule is not only a timing story: past the flare the
continuity law itself stops holding, which is the honest reason the patch ends there.

**Bounds rationale (§3).** Tacoma's throat is the anchor section at 1370 m; the limit is
1.3 × 1370 = **1781 m**. Walking north from section 31 the width crosses it at section 17
(1790 m), so the patch ends at 18; walking south nothing exceeds it, so it ends at 46.
PUG1524 and PUG1526 sit at sections 2-3 where the channel has opened to 2180 and 2090 m —
1.6× the throat, in the Point Defiance mouth flare, 2.1-2.3 km beyond the nearest kept
section. PUG1526 failed *every* M47 bar in run 1, with 2 slack events never matching
inside a 180-minute window: that is what the confined-channel assumption looks like after
the walls end.

Deception's throat is 140 m at the anchor (limit **182 m**); the width jumps to 350 m at
section 10 and 550 m at section 15, so `kept_range` is `[11, 14]` — a 300 m strip through
the pass itself. Yokeko is 2.2 km east at section 37, in the 490 m wide eastern arm. Its
single-bar first-run miss (slack max 34.8 vs 30.0 min) is spec §9's predicted phase
non-uniformity along that arm, realized.

PUG1628 (Skagit Bay channel, 48.39783, -122.57955) was never fetched, in either run; the
far-field row stays empty rather than being filled from a re-run.

## Harness notes

`sections.py` carries the flare truncation (`FLARE = 1.3`, per-pass `flare_ratio`
override, throat reference recorded in each pass doc); `certify_patch.py` carries
`reciprocal_spec` + `nearest_section`. Both are covered by unit tests
(`test_sections.py::test_kept_range_stops_at_the_flare`,
`test_certify.py::test_reciprocal_*`). Regenerating the passes for run 2 changed **only**
`kept_range` and the two new keys — every section centre, width and area is byte-identical
to run 1, so nothing in these numbers moved because the geometry moved.

`data/verdicts/*.status` holds the FitValidation exit code, which still includes the M47
timing bars and therefore reads `FAIL` for `tacoma-narrows-recip-PUG1527`. **That file is
not the verdict of record for this gate** — under §6a as amended the gate is the speed
median column above, and both in-bounds checks pass it. Run 1's verdict files are
preserved at `data/verdicts-run1/` (gitignored, like all of `data/`).
