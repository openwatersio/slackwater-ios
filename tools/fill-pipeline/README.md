# fill-pipeline

Produces `Slackwater/Resources/fill-salish.bin` + `.json` — the committed data
bundle behind `FillField` (`Slackwater/FillField.swift`), the speed-only
current-fill backdrop. Design: `docs/superpowers/specs/2026-08-20-fill-phase-b-design.md`
(authority chain: `docs/superpowers/specs/2026-08-20-current-field-composite-design.md`
§1/§2/§4a/§10 + the owner ruling there — speed fill only, no green, timing
stays with gates/patches).

Everything below runs from `tools/fill-pipeline/` unless stated otherwise.
All intermediate output lives under `data/` (gitignored) — only the final
bundle in `Slackwater/Resources/` is committed.

## Pipeline, stage by stage

### 1. Region mesh — `./region_mesh.py [fields-url]`

Subsets the SSCOFS mesh to the render clip (−125.5..−122.0 × 47.0..50.6, the
seamap bbox) and writes `data/mesh.json`: `{"file", "bbox", "elements":
[{"i", "lon", "lat", "verts": [[lon,lat]×3]}]}`. Defaults to the latest
NODD fields file when no URL is given.

Self-checks run on every invocation: `nv` connectivity base (0- vs 1-based)
is picked by whichever makes a 1000-element vertex-mean sample match the
file's own `lonc`/`latc` centroids within 100 m (hard assert — real data:
1-based wins by 0.7 m vs. a 215 km miss at base 0), and Seymour Narrows /
Tacoma Narrows must resolve to a nearest element within 600 m.

Real run: **311,447 region elements** (of 433,410 full-mesh), `data/mesh.json`
~61 MB. Seconds, not minutes — one NODD file read plus vectorized numpy.

### 2. Corpus fetch — `./fetch_region.py DAYS`

Pulls `DAYS` days of hourly surface u/v (siglay 0) for every region element
into `data/corpus/YYYYMMDD.npz` (`t`, `u`, `v`), ranged HDF5 reads over NODD,
5 threaded workers, one file per day. **Resumable**: skips any day whose
`.npz` already exists, so a killed run picks up where it left off — re-run
the same command. A day is only written if ≥20/24 hours came back; a day
below that gate is skipped and must be retried — a saved 20-23/24 day still
carries NaN in its missing hours, and `survivors.py`'s corpus loader
hard-fails on any NaN (by design, loud), so "accept the gap" is not
actually an option once a gap day gets past this gate.

Real run: **190 days**, ~4,560 hourly file reads, **~64 GB transferred
once** (~9.7 GB stored after compression). Wall clock is dominated by
network, not CPU — budget most of a working day for a cold run; a resumed
run only re-pulls the days actually missing.

### 3. Truth stations — `./stations.py`

Discovers every scoreable NOAA + CHS current station in the region (bundled
CHS-IWLS + NOAA-MDAPI discovery, 1s politeness sleep between IWLS calls) and
writes `data/stations.json`. Hard asserts on id- and slug-uniqueness.

Real run: **149 truth stations** (17 CHS, 132 NOAA). Not resumable and
doesn't need to be — one API sweep, a few minutes.

### 4. Station×element matrix — `./make_matrix.py` then `./run_matrix.sh`

`make_matrix.py` reads `data/mesh.json` + `data/corpus/*.npz` +
`data/stations.json`, finds every mesh element within 600 m of each station,
and writes `data/index.json` (station↔element pairs) plus per-pair sample
files (`data/samples/<slug>-e<elem>.json`) and truth-event files
(`data/events/<slug>-events.json`). Imports `to_sample`/`project_signed_kn`
from the spike rather than reimplementing them — one epoch-ms sample rule,
one flood-axis projection rule in the repo. **Resumable** (re-run skips
pairs already indexed — confirmed live: a second run prints `(resumed)` on
the first two lines and adds nothing new). Per-station fetch failures
(a live NOAA API quirk, or no element within 600 m) are logged and skipped,
not fatal.

`run_matrix.sh` then runs `tools/FitValidation` (file mode) over every
`data/index.json` row, writing `data/verdicts/<slug>-e<elem>.json` +
`.log` + `.done`. **Resumable** via the `.done` marker per pair — a killed
run's remaining rows are exactly what's left un-`.done`'d. Verdicts also
land under `/tmp/fit-validation/reports/`, which `run_matrix.sh` clears
per-pair before each run so a failed pair never leaves a stale report
behind.

Real run: 5,858+ pairs from the smoke check alone scale to **6,713
pair-verdicts** region-wide. Matrix cost is dominated by `swift run -c
release fit-validation` per pair (Swift process startup × ~thousands of
pairs) — budget a couple of hours for a cold run; resumed runs only redo
missing `.done` markers.

### 5. Node fitter parity gate — `./parity_check.sh [samples.json]`

One-time (or one-per-artifact-change) proof that the node shipping fitter
(`fit_batch.mjs`, running the committed `Slackwater/Resources/chs-bundle.js`
+ `chs-glue.js` in a node `vm`) reproduces a cached FitValidation fit within
`1e-9` absolute tolerance (~3 orders of magnitude above measured
node-vs-JSCore floating-point noise, ~8 below anything a downstream R²/floor
decision would see — not literal byte-identity, which doesn't hold across
engines even on identical input). Writes `data/.parity-ok` (sha256 of both
JS artifacts) — `fit_batch.mjs` refuses to run without a guard file whose
hashes match what's on disk right now, so an artifact edit after the gate
ran is caught, not silently skipped.

Must pass before step 6 runs at all.

### 6. Certify + fit + survive — `./survivors.py [--pilot N]`

The core of the pipeline. Four stages, single process:

1. **Certify** (§4a, imported unchanged from `spikes/sscofs-field/certify.py`
   — one implementation of the grading rule, never forked): grades all
   311,447 mesh elements at D = 2/3/5 km from `data/verdicts` +
   `data/index.json` + `data/stations.json`. D = 3000 m is the shipped set.
2. **Numpy prefilter** (`design_matrix`/`fit_elements` imported unchanged
   from `spikes/sscofs-field/prune_proof.py`; only the corpus loader is
   forked, to slice to certified columns per-day instead of after
   concatenating the full 311,447-column corpus): shortlist = certified ∧
   prefilter-R² ≥ 0.7 both axes. Loose on purpose — a cheap triage, not the
   floor.
3. **Node fit**: streams the shortlist through `fit_batch.mjs` via real
   files (not pipes — a ~40k-line run risks a pipe-buffer deadlock, and
   node's writes to a redirected file are synchronous, so a killed run
   leaves at most one torn trailing line). **Resumable**: scans
   `data/fits/fits.jsonl` for already-done `(elem, axis)` pairs, truncates
   any incomplete trailing line, and appends only what's missing.
4. **Final floor**: `r2 = 1 - rms²·n / Σ(v − mean(v))²` from `fit_batch.mjs`'s
   own `rms` (matches `chs-bundle.js`'s rms definition exactly, so this is
   exact, not approximate). Survivors = node-fit R² ≥ 0.8 on **both** axes →
   `data/survivors.json` + `data/SURVIVORS.md`.

`--pilot N` restricts stage 3 to the first N shortlisted elements — use it
to time-box a run before committing to the full shortlist (500 elements
timed at ~123 s real-run, extrapolating linearly to ~41 min for the full
20,501-element shortlist).

**Resume semantics, all four stages**: stage 1/2 are cheap enough to always
re-run from scratch (seconds to ~1 min); stage 3 is the expensive one and is
the stage that actually resumes via `fits.jsonl`. A killed `survivors.py`
mid-run: just re-run the same command — stages 1/2 recompute (fast), stage 3
picks up from `fits.jsonl`'s done-set, stage 4 always recomputes from
whatever `fits.jsonl` holds.

**Long-running note**: stage 3 at full scale exceeds a typical foreground
tool timeout. Launch detached (`nohup python3 -u survivors.py & disown`),
confirm the PID is alive (`pgrep`) and `data/fits/fits.jsonl` is actively
growing before leaving it unattended — a backgrounded job tied to an agent
tool's own lifecycle can be torn down silently mid-run with nothing flushed.

Real run: certified (D=3000) **63,374 of 311,447** elements (20.35%; 35,147
@ 2 km / 111,847 @ 5 km) → prefilter shortlist **20,501** → node fit (**0
fitter errors**, ~1 hour full-scale) → final survivors (R² ≥ 0.8 both axes)
**13,168**. Station verdicts: **149 truth stations, 143 matrixed, 6,713
pair-verdicts, 99 PASS / 23 FAIL / 21 unscoreable**. Rayleigh-unseparable
pairs observed: `2N2/MU2`, `N2/NU2`, `S2/T2` (S2/T2 is the expected
consequence of a 190-day window — full separation needs ~365 days; treated
as authoritative, not a defect). Seymour Narrows (1.42 kn) and Dodd Narrows
(4.52 kn) both FAIL the ≤ 0.5 kn speed-only gate, as expected — real,
strongly-tidal throats the fill correctly refuses to paint; their
neighbourhood elements come out MASKED, governed by grown patches instead
(a separate phase, out of scope here). Active Pass improved 0.62 → 0.48 kn
against official predictions with the 190-day window, and now passes.

### 7. Pack — `./pack.py`

Reads `data/survivors.json` + `data/mesh.json` (joined on element index `i`)
+ `data/stations.json` + `data/corpus/` (for the header's `corpus_window`),
prunes each element's constituents per-axis independently (kept iff
`amp ≥ max(2% of that axis's own max amplitude, 0.005 kn)` — a real,
per-element, per-axis floor computed at pack time, not a shared/estimated
one), and writes `Slackwater/Resources/fill-salish.bin` + `.json`. Hard
size gate at 40 MB (`SystemExit`, survives `python -O`); hard re-check that
every survivor's `r2_u`/`r2_v` actually clears 0.8 (a regression upstream in
`survivors.py` fails loudly here, not silently in the shipped bundle).
Not resumable and doesn't need to be — one deterministic pass over already-
computed inputs, seconds.

Real bundle: **2,614,613 bytes (2.61 MB)**, 13,168 elements — well under the
40 MB gate (and under the composite spec §10 proof's 13.25 MB extrapolate,
because region certification — not constituent pruning — is what keeps the
bundle small; §10 measured a mean of 21.3/23 constituents kept per axis on
its box-scale proof run, and this real region-scale bundle keeps a mean of
**16.8 of 23 possible constituents per axis** (33.5 combined across both
axes per element), so the floor prunes harder here too). Generated
2026-08-21T18:57:30Z; `bin_sha256` `e16c1aaf…` (full digest in the header
JSON, `Slackwater/Resources/fill-salish.json`'s `bin_sha256` field).

Per-element Z0 mean-flow offset (`offset_u`/`offset_v`, kn) ships in this
bundle too, as of the final-review fix — a real, nonzero least-squares mean
flow from the fitter (`fits.jsonl`'s `offset`), not zeroed out. It's a fit
over this bundle's own 190-day corpus window, so it carries that window's
seasonal mean circulation, not a long-term climatological mean (stated in
the header's `offset_note`, not hidden) — grew the bundle by 4 bytes/element
(2 x f16) over the pre-offset 2.56 MB.

## End-to-end reproduce

```sh
cd tools/fill-pipeline
./region_mesh.py                 # data/mesh.json
./fetch_region.py 190            # data/corpus/*.npz — resumable, re-run to resume
./stations.py                    # data/stations.json
./make_matrix.py                 # data/index.json + data/samples + data/events — resumable
./run_matrix.sh                  # data/verdicts/*.json — resumable via .done markers
./parity_check.sh                # data/.parity-ok — must pass before survivors.py
./survivors.py                   # data/survivors.json + data/SURVIVORS.md — stage 3 resumable
./pack.py                        # ../../Slackwater/Resources/fill-salish.{bin,json}
```

Then from the repo root: `xcodegen generate` (folder-based resource
inclusion picks the new bundle up automatically — no `project.yml` edit
needed, same as `chs-bundle.js`/`fill-fixture.bin` already in
`Slackwater/Resources/`), then run the test suite; `FillFieldTests.swift`'s
`testRealBundleGoldenElement` activates automatically once
`fill-salish.bin` exists at that path.

Refitting later (a release decision, not automatic — constants are stable
between refits per the design's "fitted-model-does-not-expire" semantics):
re-run steps 2 onward against a fresh corpus window, then re-pack and
re-pin the golden test's expected value (it's a regression pin against
*this* bundle's fit, not an invariant that survives a refit).

## Single-implementation provenance

Two rules this pipeline exists to honor, not to re-litigate:

- **§4a grading** (`station_verdicts`/`grade_elements`) and the **numpy
  prefilter** (`design_matrix`/`fit_elements`) are imported from
  `spikes/sscofs-field/certify.py` / `prune_proof.py`, never forked.
- **The shipping fitter is the committed JS artifacts** run in node
  (`fit_batch.mjs` loading `Slackwater/Resources/chs-bundle.js` +
  `chs-glue.js`), the same precedent as `spikes/chs-currents-fit/node-control.mjs`.

`region_mesh.py`/`fetch_region.py`/`stations.py`/`make_matrix.py` legitimately
fork their spike counterparts (region bbox and output paths differ) — each
carries a provenance comment saying so in its header.
