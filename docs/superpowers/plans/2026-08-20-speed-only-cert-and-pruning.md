# Speed-Only Certification Rule + Bundle-Pruning Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the two prerequisites the owner ruling requires before any fill pixel ships: a specified speed-only certification rule executed over the spike's real data (certified-region geometry for the box), and a measured bundle-pruning proof against the ≤ 40 MB budget.

**Architecture:** Two new Python scripts in `spikes/sscofs-field/` consume the existing spike artifacts (mesh subset, 60-day corpus, 2,004 fit verdicts, truth stations). `certify.py` grades every box element by its nearest scoreable station's speed-only verdict and emits certified-element sets + GeoJSON. `prune_proof.py` fits all 73,550 box elements at once (vectorized lstsq against the shipping 23-constituent basis frequencies — sizing fits, explicitly not shipping fits), applies R² and energy floors, quantizes, and measures certified-region bytes with a bounded extrapolation to the render region. A spec amendment specifies the rule before the code implements it.

**Tech Stack:** Python via `uv run --with numpy` (+`pytest` for tests), node (one-liner to extract basis speeds from the committed `chs-bundle.js`), existing spike data (all gitignored, on disk in this worktree).

## Global Constraints

- **Owner ruling (spec status block, verbatim authority):** fill ships where speed certifies (≤ 0.5 kn median peak-speed bar at best element); throats stay grown-patch territory; stations/patches are sole authority on timing/transitability; fill ramp never contains green.
- **Certification rule parameters (fixed by this plan, sensitivity reported, not re-decided by implementers):** grading distance D = 3 km (report 2 km and 5 km sensitivity); a station grades only if scoreable (best element has ≥1 published extremum ≥ 0.75 kn — cherry-point is the known unscoreable); element certified iff nearest scoreable station within D passed speed-only; beyond D of every scoreable station → uncertified (absent, never calm); an element graded by a FAILED station is uncertified (mask), matching "throat failures stay grown patches".
- **Sizing-fit floors (fixed):** tidal R² ≥ 0.8 per element per axis (report 0.7/0.9 sensitivity); constituent energy floor: keep constituents with fitted amplitude ≥ max(2% of that element's largest amplitude, 0.005 kn); quantization: per kept constituent per axis 5 B (1 B id + f16 amp + f16 phase) + 8 B/element header.
- **Budget:** certified-region bundle ≤ 40 MB after extrapolation; extrapolation must be bounded by the full-mesh element count (433,410) — the spike's density method overshot and was called out in review.
- **Honesty rules carried over:** numpy sizing fits are labeled as such everywhere they appear (they size the bundle; the shipping fitter remains chs-glue/fitTides); uncertified renders as absent; no green anywhere in any deliverable.
- Everything under `spikes/sscofs-field/`; data dirs gitignored; scripts committed; branch `field-cert`.
- Basis: the 23 shipping constituents `["M2","S2","N2","K2","K1","O1","P1","Q1","M4","MS4","MN4","2N2","MU2","NU2","L2","T2","J1","MM","MSF","MF","M6","S4","M3"]` — angular speeds extracted programmatically from `Slackwater/Resources/chs-bundle.js` (node vm; the file defines `CHSConstituents`), falling back to the NOAA published speeds table keyed by these names only if the bundle doesn't expose speeds. Never hand-type speeds without a source.

## File Structure

```
docs/superpowers/specs/2026-08-20-current-field-composite-design.md   # Task 1: §4a + §10 amendment
spikes/sscofs-field/
  certify.py          # Task 2 → certified/certified.json + certified.geojson + CERTIFY.md
  test_certify.py     # Task 2 unit tests (grading logic, synthetic)
  prune_proof.py      # Task 3 → certified/PRUNING.md (+ sizing arrays, gitignored)
  test_prune.py       # Task 3 unit tests (fit recovery + quantization size math, synthetic)
  README.md           # Task 4: outcome addendum
```

---

### Task 1: Spec amendment — §4a speed-only certification + §10 pruning-proof method

**Files:**
- Modify: `docs/superpowers/specs/2026-08-20-current-field-composite-design.md`

**Interfaces:**
- Produces: the normative text Tasks 2–3 implement. Task 2/3 briefs restate the parameters; this task writes them into the spec.

- [ ] **Step 1: Insert §4a after §4** (keep §4's existing marker and text untouched):

```markdown
## 4a. Speed-only certification (the fill channel's gate) — per the owner ruling

Replaces the five-bar rule for the BACKDROP FILL only. Gates/patches keep §4's
timing bars untouched.

- **Grading stations:** a truth station grades iff scoreable — its best element
  carries ≥ 1 published extremum ≥ 0.75 kn. Unscoreable stations (cherry-point)
  grade nothing: their neighbourhood is uncertified, absent, never calm.
- **Verdict:** a scoreable station PASSES iff its best element's median
  peak-speed error ≤ 0.5 kn (the existing bar, speed row only).
- **Element rule:** an element is certified iff its nearest scoreable station
  lies within D = 3 km and PASSED. Nearest-failed → masked (throats are
  grown-patch territory). No scoreable station within D → uncertified.
- **Sensitivity is part of the record:** certified counts at D = 2/3/5 km ship
  with the geometry so the choice of D stays legible.
- **Fill semantics:** certified elements feed the speed fill only. The ramp
  never contains green. Nothing here carries timing.

## 10. Bundle-pruning proof (the ≤ 40 MB gate)

Method, so the number is reproducible: vectorized least-squares sizing fits
(23-constituent shipping basis frequencies, mean term, hourly 60 d corpus) for
every box element — SIZING fits; the shipping fitter remains chs-glue's
fitTides. Floors: per-axis tidal R² ≥ 0.8 (elements below are uncertified —
weakly tidal water is not painted); per-element constituent energy floor
amp ≥ max(2 % of element max, 0.005 kn). Quantization: 5 B per kept
constituent per axis + 8 B/element. Extrapolation to the render region scales
by certified-area density and is CAPPED by the full-mesh element count.
```

- [ ] **Step 2: Update the status block's "Still required" sentence** to point at §4a/§10 instead of calling them unwritten.
- [ ] **Step 3: Commit** — `docs(spec): §4a speed-only certification rule + §10 pruning-proof method (owner ruling prerequisites)`

### Task 2: certify.py — certified-region geometry from real verdicts

**Files:**
- Create: `spikes/sscofs-field/certify.py`, `spikes/sscofs-field/test_certify.py`

**Interfaces:**
- Consumes: `mesh/elements.json`, `samples/index.json`, `results/*.json`, `truth/stations.json`.
- Produces: `certified/certified.json` — `{"D_m": 3000, "elements": [<certified element ids>], "stations": [{"slug", "verdict": "PASS"|"FAIL"|"UNSCOREABLE", "speed_med"}], "sensitivity": {"2000": <count>, "3000": <count>, "5000": <count>}}`; `certified/certified.geojson` (Point per element, `certified` property — eyeball artifact); `certified/CERTIFY.md` (stats: station verdict counts — expect 40 PASS / 13 FAIL / 1 UNSCOREABLE; % of box elements certified/masked/no-data at each D).

- [ ] **Step 1 (TDD): write `test_certify.py`** with synthetic geometry: three stations (PASS at origin, FAIL 4 km east, UNSCOREABLE 4 km north) and a handful of elements placed to pin every branch: element 1 km from PASS → certified; 1 km from FAIL → masked; equidistant-ish but nearest-FAIL → masked; 2.5 km from PASS with FAIL at 3.5 km → certified; 1 km from UNSCOREABLE only → uncertified; 10 km from everything → uncertified. Import `grade_elements(elements, stations, D_m)` from certify.
- [ ] **Step 2: run — RED** (`uv run --with pytest,numpy pytest -q spikes/sscofs-field/test_certify.py`).
- [ ] **Step 3: implement.** Station verdicts derived exactly as the final RESULTS.md did post-sentinel-fix: per station, rows from results/*.json via index; drop `speedMedianKn < 0` rows; UNSCOREABLE if no rows survive; else PASS iff best (min) `speedMedianKn ≤ 0.5`. `grade_elements`: nearest scoreable station by euclidean metres (lat/lon × 111320 / cos-lat — the spike's convention); apply the rule. Main emits the three outputs. GeoJSON properties: `certified` ∈ {"yes","masked","none"}.
- [ ] **Step 4: run — GREEN**, then run `./certify.py` for real; sanity: Dodd/Deception/Porlier/Race neighbourhoods masked; cherry-point neighbourhood "none"; report the three sensitivity counts.
- [ ] **Step 5: Commit** — `spike(sscofs-field): speed-only certification geometry (§4a) from spike verdicts`

### Task 3: prune_proof.py — measured bundle size for certified elements

**Files:**
- Create: `spikes/sscofs-field/prune_proof.py`, `spikes/sscofs-field/test_prune.py`

**Interfaces:**
- Consumes: `corpus/*.npz`, `mesh/elements.json`, `certified/certified.json`, basis speeds from `Slackwater/Resources/chs-bundle.js` (extract via `node -e` with a vm context; fall back to NOAA speeds table keyed by the 23 names only if unexposed — record which path was used).
- Produces: `certified/PRUNING.md` — R² distribution, elements surviving the R² floor, constituents/element distribution after energy floor, measured bytes for certified box elements, capped render-region extrapolation, **verdict vs 40 MB** at D=3 km (and the 2/5 km sensitivities), floors sensitivity (R² 0.7/0.9).

- [ ] **Step 1 (TDD): write `test_prune.py`**: (a) synthetic recovery — build 60 d hourly series from 3 known constituents (M2/K1/M4 amplitudes 1.0/0.4/0.1 kn, known phases) + noise σ=0.05, assert `fit_elements` recovers amplitudes within 0.02 kn and R² > 0.95; (b) quantization math — `bundle_bytes(kept_counts)` for known inputs equals `sum(8 + 5*2*k)`; (c) energy floor — amplitudes `[1.0, 0.03, 0.004]` with floor `max(0.02, 0.005)` keeps exactly 2.
- [ ] **Step 2: run — RED.**
- [ ] **Step 3: implement.** Vectorized: design matrix A `[n_hours × (2·23+1)]` (cos/sin at each basis speed + mean; t in hours from corpus epoch), solve `pinv(A) @ U` once for all elements per axis (U is `[n_hours × 73550]` from concatenated sorted shards; NaN rows dropped). R² per element per axis; keep elements certified ∧ min-axis R² ≥ 0.8. Energy floor per element on `hypot(a_cos, a_sin)` amplitudes across both axes (a constituent is kept if it survives on either axis; count kept per element). Bytes = `8 + 5·2·kept` per surviving element. Extrapolate: certified-area density → render region, capped at 433,410 total. Label every output line "sizing fits (numpy lstsq) — not the shipping fitter".
- [ ] **Step 4: run — GREEN**, then `./prune_proof.py` for real (the 1440×73550 matmul is a few seconds; memory ~1.7 GB f32 — fine on the Studio). Read PRUNING.md; the verdict line must state MB vs 40 MB plainly, pass or fail.
- [ ] **Step 5: Commit** — `spike(sscofs-field): bundle-pruning proof (§10) — measured certified-region size`

### Task 4: Close-out docs

**Files:**
- Modify: `spikes/sscofs-field/README.md` (addendum section after the postscript), spec status block (final state), `docs/chs-data-model.md` §6 only if the pruning verdict changes the standing ruling's caveats.

- [ ] **Step 1:** README addendum "Prerequisites executed (2026-08-20)": certification geometry summary (station verdicts, % certified at D=3 km, sensitivity), pruning verdict (MB vs 40), both with reproduce commands; explicit statement of what remains before the fill ships (Phase B engineering: real fits via shipping fitter for certified elements, mask shipping format, fill renderer — pointers, not plans).
- [ ] **Step 2:** Spec status block: replace "Still required before the fill ships: …" with the executed outcomes (§4a geometry produced; §10 verdict), leaving whatever failed (if the pruning proof fails 40 MB, say so and mark the fill blocked on it — record, don't rescue).
- [ ] **Step 3: Commit** — `docs: prerequisites executed — certification geometry + pruning verdict`; push branch; open PR (internal repo).

## Self-review notes
- Both §3-style honesty rules preserved: unscoreable → absent; failed → masked; extrapolation capped; sizing fits labeled.
- Parameters (D, floors, quantization) fixed here so implementers don't re-decide policy; sensitivity reporting keeps them legible for Bryan.
- The 2/5 km and R² 0.7/0.9 sensitivities are cheap (same arrays, different thresholds) — required output, not optional.
