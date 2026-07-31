# CHS currents fit — M47 validation pass (2026-07-31)

The follow-on M3 named: the fit method was validated for tides only, and gates are
safety-critical slack timing — "shipping unvalidated fitted slack times would be wrong water
under a trusted name." This pass validates the fit per gate against CHS's own published
events, on the app's exact shipping path, and ships **only the passers**.

## Method

Harness: `tools/FitValidation` grew a `--current` mode (same tool, same JS artifacts, same
resolve-by-position rule) — run per gate over the 19 registry CHS gates:

1. **Resolve by position** (never name): nearest IWLS station serving `wcsp1` within 3 km of
   the registry position. All 19 resolved at ≤0.06 km with matching names.
2. **Fetch** `wcsp1` (speed) + `wcdp1` (direction), 210 days ending today 00Z, 7-day chunks,
   2.5 s apart, disk-cached. **Project** onto the CHS flood axis from `/metadata`:
   `signed = speed · cos(dir − floodDirection)` — chs-constituents' own projection.
3. **Fit in JavaScriptCore** with the app's committed `chs-bundle.js` + `chs-glue.js`
   (`fitTides` is a generic harmonic fit — chs-constituents was built for currents first).
   Two windows per gate from one fetch: the full **210 d** and the trailing **60 d** (the
   tide window).
4. **Predict with TideEngine's `CurrentStation`** — the app's shipping synthesis: slacks are
   velocity value-zeros, maxima are slope-zeros signed flood/ebb.
5. **Score against CHS's own published `wcp1-events`**, held out +28..+35 days in the future:
   slack timing (median/max, every observed slack must match within 180 min), extremum timing
   (median/max, extrema ≥0.75 kn), peak speed error at matched extrema, and the sign of
   modelled velocity at CHS's own extremum instants (axis-flip test).

## The bar (set before scoring)

Slack is the safety quantity — a gate is transited *at slack* — so it gets the tightest
numbers, tighter than the engine's ±20-min maxima bar per chs-online-design §6a:

| Quantity | Bar | Why |
|---|---|---|
| Slack timing median | ≤ 15 min | the planning margin a skipper actually uses (arrive 15 early) |
| Slack timing worst | ≤ 30 min | one slack >30 min off is wrong water, whatever the median says |
| Extremum timing median | ≤ 20 min | the engine's established maxima bar (= chs-constituents "medium" tier) |
| Peak speed median error | ≤ 0.5 kn | the number a skipper reads off the peak |
| Axis | no systematic flip | wrong-sign ≥60% of extrema quarantines (chs-constituents' test) |

PASS = all five at the 210-day window. A gate whose IWLS station serves no fittable series
would be FAIL-for-fitting (online-events-only candidate); none of the 19 was — every gate
serves `wcsp1`/`wcdp1`/`wcp1-events`.

## Results — 19 gates, 210 d fit, validated vs published events 28–35 d out

All 19 gates serve fittable series and resolved by position at ≤0.06 km. Timing in minutes,
speed in knots; every observed slack matched within 180 min at every gate; wrong-sign 0
everywhere (no gate is axis-flipped).

| Gate | fit rms | slack med/max | extrema med/max | speed med | Verdict |
|---|---|---|---|---|---|
| Active Pass | 0.05 | 2.4 / 4.0 | 1.1 / 2.4 | 0.06 | **PASS** |
| Arran Rapids | 0.63 | 4.9 / 11.4 | 14.5 / 34.5 | 0.66 | FAIL — speed |
| Beazley Passage | 0.53 | 3.6 / 10.5 | 16.2 / 39.3 | 0.51 | FAIL — speed (near miss) |
| Blackney Passage | 0.16 | 5.0 / 24.7 | 8.7 / 25.2 | 0.07 | **PASS** |
| Dent Rapids | 0.46 | 3.2 / 8.6 | 20.1 / 38.0 | 0.27 | FAIL — extrema med (near miss) |
| Dodd Narrows | 0.37 | 2.1 / 18.6 | 13.1 / 26.0 | 0.16 | **PASS** |
| First Narrows | 0.06 | 2.8 / 5.8 | 1.9 / 3.0 | 0.09 | **PASS** |
| Gabriola Passage | 0.39 | 19.2 / 33.1 | 14.9 / 38.2 | 0.22 | FAIL — slack |
| Gillard Passage | 0.39 | 3.7 / 9.1 | 12.4 / 22.8 | 0.42 | **PASS** |
| Hole in the Wall | 0.54 | 3.6 / 9.6 | 13.7 / 26.9 | 0.42 | **PASS** |
| Johnstone Strait Central | 0.04 | 1.3 / 5.4 | 4.5 / 12.8 | 0.05 | **PASS** |
| Juan de Fuca East | 0.22 | 18.1 / 84.5 | 22.6 / 46.7 | 0.11 | FAIL — slack |
| Porlier Pass | 0.38 | 2.2 / 18.8 | 10.6 / 38.1 | 0.16 | **PASS** |
| Race Passage | 0.32 | 4.2 / 11.6 | 9.9 / 50.4 | 0.44 | **PASS** |
| Sechelt Rapids | 1.29 | 15.5 / 39.5 | 11.7 / 55.7 | 0.94 | FAIL — slack + speed |
| Second Narrows | 0.35 | 5.9 / 13.5 | 20.6 / 48.1 | 0.26 | FAIL — extrema med (near miss) |
| Seymour Narrows | 0.00 | 0.2 / 1.0 | 0.3 / 0.5 | 0.00 | **PASS** |
| Tillicum Bridge | 0.43 | 19.0 / 93.0 | 19.1 / 96.5 | 0.15 | FAIL — slack |
| Weynton Passage | 0.21 | 3.0 / 19.2 | 5.6 / 25.5 | 0.12 | **PASS** |

**11 of 19 pass. Those 11 ship in build 12; the 8 failures are absent from the bundle**
(commented with their numbers in `tools/gen-chs-gates.mjs`).

## Findings

1. **210 days is the window, and it is not negotiable.** At the tide path's 60-day window
   only 4 of 19 pass (Active Pass, First Narrows, Johnstone Strait, Seymour) — K1/P1, which
   drive PNW diurnal inequality, are Rayleigh-unseparable below 183 d and the slack error
   roughly triples (Dodd: slack median 2.1 → 15.1 min, extrema 13.1 → 22.8). The app fits
   currents at 210 d (`ChsFitService.currentFitDays`); tides stay at their validated 60 d.
2. **What fails is the physics, not the method.** Every failure is a violent nonlinear
   rapids (Arran, Beazley, Dent, Sechelt — fit rms 0.5–1.3 kn against a 23-constituent
   linear basis), a weak slow-reversing station where the zero crossing is ill-posed (Juan
   de Fuca East, Tillicum, Gabriola), or an urban narrows with the same character (Second
   Narrows). This matches chs-constituents' own tiering of the same stations.
3. **Near misses stay out.** Beazley (speed 0.51 vs 0.50), Dent (extrema 20.1 vs 20.0) and
   Second Narrows (20.6) missed by a rounding error's width. The bar was set before scoring;
   admitting them after the fact is bar-shopping. Revisit with a method change (e.g. a
   relative peak-speed criterion — 0.5 kn at a 7 kn rapids is 7%) — not with a rerun.
4. **JSCore ↔ Node parity holds for currents.** The same Dodd Narrows sample bytes through
   the app's `chs-bundle.js` under Node vm: offset diff 5.6e-17, worst amplitude diff
   8.9e-16, worst phase diff 5.7e-14 ° — machine epsilon (FP reassociation between engines),
   physically nil.
5. **No gate is events-only.** The registry's 19 all carry `wcsp1`/`wcdp1`/`wcp1-events`, so
   the online-events-only fallback path was not needed and was not built.

## Files

`tools/FitValidation` `--current` mode (the harness — fit in JSCore, predict in TideEngine,
score vs `wcp1-events`) · `node-control.mjs` (parity check: the same sample bytes through the
app's `chs-bundle.js` under Node `vm`, `node node-control.mjs <reportsDir> <gate-slug>`) ·
per-gate JSON reports + the exact sample bytes handed to JSCore land in the run's cache dir
(CHS data — never committed).

Rerun one gate:

```sh
cd tools/FitValidation
swift run fit-validation --current "Dodd Narrows" 49.1344 -123.8171 /tmp/chs-currents
```
