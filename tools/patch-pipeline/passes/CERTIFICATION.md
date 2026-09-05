# Shipped inventory — all five Tier-1 passes

The phase's verdict of record, in one table. "Ships?" is whether a
`passes/<slug>.json` is committed *and* survives to a non-empty `kept_range`
after both the §3 flare rule and the §6b.2 sensitivity sweep — the two
narrowing steps are sequential, and a pass can clear the first and still be
cut to nothing by the second (Deception).

| pass | final kept_range | cells | ships? | why not |
|---|---|---|---|---|
| tacoma-narrows | `[18, 46]` | 56 | **yes** | — |
| seymour-narrows | `[19, 24]` | 10 | **yes** | — |
| deception-pass | `[11, 14]` flare → `[12, 12]` after sensitivity | 0 | **no** | single section after the sensitivity shrink — no interval to triangulate, zero cells |
| dodd-narrows | `[18, 18]` (flare only; sensitivity never runs) | 0 | **no** | anchor instability 19.7–20.5 % across all three sensitivity variants, blows the 10 % bar |
| porlier-pass | `[20, 25]` (flare only; sensitivity never runs) | 0 | **no** | anchor instability 12.7 % on the `datum=CD` axis (blows the 10 % bar) + springs plausibility +46 % over published |

Three of five ship. The §6a RUN method-certification record for the two US
passes (Tacoma, Deception) is immediately below; the §6b BC record (Seymour,
Dodd, Porlier, including the Dodd/Porlier failures in detail) follows it
further down this file.

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

Deception Pass generates no in-bounds pair: the flare rule leaves `[11, 14]`, but the
§6b.2 sensitivity sweep shrinks that further to `[12, 12]` — a single section, zero
cells, ships nothing (see the shipped-inventory table below) — and its only candidate
station, Yokeko PUG1629, is 2.2 km east of even the flare-stage strip. It does not gate;
it is covered by the Tacoma certification, which is what a method-certification channel
is for.

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
section 10 and 550 m at section 15, so the flare rule alone leaves `kept_range [11, 14]`
— a 300 m strip through the pass itself. Deception's anchor itself is not unstable (8.06 /
8.06 / 5.4 % across the three sensitivity variants, comfortably inside the 10 % bar — see
`anchor_stability` in the committed `deception-pass.json`); what narrows `[11, 14]` to
`[12, 12]` is the §6b.2 **per-section** truncation gate — one section below the anchor and
two above it move more than max(10 %, 0.25 kn) at spring peak under at least one variant
(`sensitivity.dropped_below: 1`, `dropped_above: 2`, same file) and get dropped, leaving a
single surviving section with no neighbour to triangulate an interval from — zero cells,
not a special-cased omission (`pack.py`'s own docstring says as much). Yokeko is 2.2 km
east at section 37, in the 490 m wide eastern arm. Its single-bar first-run miss (slack
max 34.8 vs 30.0 min) is spec §9's predicted phase non-uniformity along that arm, realized.

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

## Shipped-scale addendum (reach-mean estimator, spec §3 third amendment)

The scales this certification was graded against are stale: `tools/patch-pipeline/passes/CERTIFICATION.md`
above cites `scales[43] = 0.9064` (fwd) and the renormalized reciprocal `1.1033`, computed
before the owner ruling of 2026-08-21 (third amendment) made `A(x)` the **reach-mean**
cross-section area over ±half a section spacing rather than the raw single-transect area
— a single transect at a sharp throat is placement-noisy (measured 12.7 % anchor-area
swing at Deception's 140 m gut under a half-spacing seed shift), so the estimator averages
each section with its two neighbours, uniformly, across every pass. The committed
`tacoma-narrows.json` now ships `scales[43] = 0.912` (fwd) / reciprocal `1.0965` — a
~0.62 % drift from the certified values, from the estimator swap alone (anchor identity
`scales[31] = 1.0` is unchanged by construction on either estimator).

**Immateriality (re-reviewer's verdict, not re-derived here):** a ~0.6 % scale drift moves
each row's error terms by ~0.6 % of the predicted speed — hundredths of a knot — against
this gate's 0.18 kn (PUG1528, `0.5 − 0.32`) and 0.30 kn (recip, `0.5 − 0.20`) margins. Both
PASS verdicts on the §4a speed-only bar (`speedMedianKn <= 0.5`) are robust to that drift.
No FitValidation re-run required; this addendum records the shipped-vs-certified numbers
and the reasoning rather than re-grading.

---

# BC passes — §6b verdicts (Dodd, Seymour, Porlier)

No check station exists at any of the three, so **the §6a certification harness does not
run here** — that is precisely why the US pair certified the method first (§6a, Task 4:
CLEARED). What follows is the §6b per-patch record: anchor identity, the sensitivity
sweep's anchor-stability gate, the flare/sensitivity bounds, and the §6b.3 springs
plausibility number. Bathymetry for all three is the **GSC Canada West Coast
Topo-Bathymetric DEM, 10 m, v2** (NRCan, OGL – Canada; owner ruling 2026-08-21 makes it the
primary Canadian source, NONNA-10 the recorded fallback). Its vertical datum is **CHS chart
datum, elevation-up** — stated in the dataset's own lineage ("data elevations were
re-calculated to the vertical chart datum used by the Canadian Hydrographic Service") and
checked empirically against the certified NOAA MLLW surface at Deception Pass, where the
two overlap: median difference **+0.41 m** over 6608 wet cells (p25 −0.24, p75 +1.07). An
MSL-referenced grid would have read ~1.41 m deeper there. So `tile_value: "elevation"` and
a real non-zero `cd_to_mwl_m`, exactly as for the US pair.

## Verdict: 1 of 3 ships. Seymour clears; Dodd and Porlier fall to the no-patch fallback

| pass | sections | anchor | throat (ref) | kept_range | anchor stability (worst variant) | §6b.3 springs | ships? |
|---|---|---|---|---|---|---|---|
| **seymour-narrows** | 32 @ 150 m | 23 | **770 m** (anchor section) | flare `[18, 25]` → sensitivity **`[19, 24]`** | **7.24 %** (`shift−0.5`) — clears the 10 % bar | max scale 1.1112 × 15.60 = **17.33 kn** vs published **15.60** → **+11.1 %**, inside ~15 % → **PASS** | **yes** |
| **dodd-narrows** | 42 @ 50 m | 18 | **80 m** (strip minimum — anchor is not the throat) | flare `[18, 18]`; sensitivity **never completed** | **19.91 / 20.52 / 19.67 %** — all three variants blow the 10 % bar | 1.0 × 9.43 = **9.43 kn** vs **9.43** (+0.0 %) — trivially true on a one-section range, see below | **no** |
| **porlier-pass** | 40 @ 100 m | 25 | **960 m** (strip minimum — anchor is not the throat) | flare `[20, 25]`; sensitivity **never completed** | shift ±0.5: 3.62 / 4.35 % — but `datum=CD` **12.71 %** | max scale 1.4602 × 9.76 = **14.25 kn** vs published **9.76** → **+46.0 %** → **FAIL** | **no** |

"Ships no patch" is the pre-decided fallback for an anchor-unstable pass (owner ruling
2026-08-21, third amendment), not an escalation. It is implemented by **not committing
`passes/dodd-narrows.json` or `passes/porlier-pass.json` at all**: `pack.py` globs
`passes/*.json` and has no gate of its own, so a committed artifact *is* a shipped patch.
The inputs are committed, so both runs reproduce from `./sections.py <slug>` and both
`SystemExit`s reproduce from `./sensitivity.py <slug>`.

## The binding constraint at both failures is the datum axis, not anchor placement

The `datum=CD` variant recomputes `A(x)` at chart datum instead of MWL — for these passes
that is 3.08 m (Dodd) and 2.59 m (Porlier) of water removed from a cross-section that
includes broad shallow margins. Anchoring each pass at the DEM's own throat instead of the
CHS gate position (a diagnostic run, not a committed input) does **not** rescue either:

| diagnostic: anchor moved to the DEM throat | `shift+0.5` | `shift−0.5` | `datum=CD` |
|---|---|---|---|
| dodd-narrows @ section 20 (80 m gut) | 8.60 % | 9.58 % | **22.67 %** |
| porlier-pass @ section 21 (960 m) | 3.72 % | 3.51 % | **12.52 %** |

Dodd's gut carries ~12 m of water over an 80 m width; 3.08 m of datum is a quarter of its
depth, so its cross-section area is a function of the tide stage in a way Seymour's 90–150 m
channel simply is not (`datum=CD` moves Seymour's anchor area by 4.56 %). This is spec §2's
"in shallow throats it is exactly the kind of instability the shrink rule handles",
realized — except that at Dodd and Porlier it is the *anchor* that is unstable, so the
shrink rule never gets to run. The honest upgrade path is the one the spec already names
and defers: a tide-stage-dependent `A(x, t)`.

Dodd's spacing is not the cause: re-run at 100 m (the spec's stated 100–200 m band) the
anchor area swings **27.62 / 33.64 / 20.33 %**, worse than 50 m's 19.91 / 20.52 / 19.67 %.
Recorded in `inputs/dodd-narrows.json` notes.

## Second finding: at Dodd and Porlier the gate is not at the hydraulic control

Both CHS gate positions sit in water materially wider than the pass's own throat, and the
published spring maximum is a *throat* number. The consequences differ only because the
flare rule catches one of them:

- **Dodd** — anchor section 18 is 160 m wide (reach-mean area 2322 m²) and sits ~130 m SSE
  of the DEM's 80 m gut (section 20, 1216 m²). The continuity law therefore implies
  **18.01 kn** at the gut against a published 9.43 — a 91 % over-prediction. It is **not
  shipped**: the flare rule (limit 1.3 × 80 = 104 m) terminates the patch at `[18, 18]`,
  the anchor section alone, so the gut is outside the bounds and the patch makes no claim
  about it. The §6b.3 number in the table above (+0.0 %) is therefore true but vacuous —
  a one-section range can only ever read the gate's own value back. Recorded so that
  "Dodd passes springs" is never read as evidence.
- **Porlier** — anchor section 25 (reach-mean 30 129 m²) is at the pass's NE opening,
  ~400 m NE of the narrowest section 21 (20 634 m²), which **is** inside the flare bounds.
  So the over-prediction lands inside the patch: **14.25 kn vs 9.76 published, +46.0 %**.
  This is a clean §6b.3 FAIL, independent of the anchor-stability failure above, and it
  would still fail if the stability gate were cleared.

The fix, if the owner wants one, belongs in `station-metadata` (the workspace's source
of truth for station *position*), not in this pipeline: the CHS current-station positions
for Dodd (49.134351 / −123.817132) and Porlier (49.015 / −123.585 — three decimals, and
exactly round) are nominal chart labels, not the point the predictions describe. Seymour's
(50.133333 / −125.35) happens to land on its control section, which is why it is the pass
that clears. No position was corrected here.

## Throat widths read wider than the navigable channel — by design

The pipeline measures the **contiguous wet run at MWL**, not the charted fairway. Seymour's
770 m matches the chart because its shores are steep-to; **Porlier's 960 m is ~2× the
~400–500 m fairway** because the pass's drying ledges are covered at MWL and the wet run
crosses them. Swept over every orientation at the narrows, the minimum wet width there is
760–1020 m — the geometry, not a mis-traced thalweg. Dodd's 80 m matches the chart (a rock
gut has no ledges to cover). The convention is the same one the US pair certified under;
it is noted here because a reader comparing 960 m to a chart will otherwise assume an error.

## Provenance and reproduction

- Anchors: CHS gates, identity from `station-metadata/data/registry.json` (no
  provider-minted station code is committed — the registry ships identity, the id resolves
  under the operator's own provider licence). Flood axes are the IWLS station metadata
  `floodDirection`: Dodd **355°** (floods N), Seymour **180°** (floods S), Porlier **30°**
  (floods NE, out into the Strait of Georgia). Every seed is drawn in the flood direction
  and clears `sections.py`'s 60° orientation assert.
- `spring_max_kn` is the 2026 annual maximum over every `EXTREMA_FLOOD` / `EXTREMA_EBB`
  event in each gate's CHS IWLS `wcp1-events` series (~2820 events per station):
  **Dodd 9.43 kn** (2026-05-17, new-moon flood), **Seymour 15.60 kn** (2026-06-15 flood),
  **Porlier 9.76 kn** (2026-05-17 flood). All three match the Sailing Directions / tide-table
  figures the spec quotes (~9, 15–16, ~9).
- `cd_to_mwl_m` is the IWLS **MWL** height above chart datum at the nearest tide station:
  Dodd **3.08 m** (Nanaimo Harbour, 3.4 km; Ladysmith on the other side reads 2.53 m),
  Seymour **2.88 m** (the Seymour Narrows tide station itself), Porlier **2.59 m** (the
  Porlier Pass tide station itself).
- Thalweg seeds are not hand-traced from a rendered picture: each is a least-cost route
  (cost 1/depth², land impassable) between a point in the water either side of the pass,
  decimated to ~1 spacing. `sections.py`'s relief-gated, slew-capped refinement owns the
  final centreline.
- Tile windows, the archive's sha256s, the datum finding and the OGL – Canada licence note
  are in `data/tiles/<slug>/MANIFEST.json` (gitignored, like all tiles).
- Review plots (§6b.4 owner bounds review):
  `docs/superpowers/specs/grown-patches-plots/plot-tacoma-narrows.png`,
  `docs/superpowers/specs/grown-patches-plots/plot-deception-pass.png`,
  `docs/superpowers/specs/grown-patches-plots/plot-seymour-narrows.png`,
  `docs/superpowers/specs/grown-patches-plots/plot-dodd-narrows-throat.png`,
  `docs/superpowers/specs/grown-patches-plots/plot-porlier-pass.png`.
