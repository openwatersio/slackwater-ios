# Fill Phase B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the fill-channel data path per `docs/superpowers/specs/2026-08-20-fill-phase-b-design.md`: region corpus → region certification → shipping-fitter constants → committed ≤40 MB bundle → Swift `FillField` provider.

**Architecture:** Production pipeline in `tools/fill-pipeline/` (Python for data movement/numpy prefilter, node for shipping fits with the committed JS artifacts, one pack script). §4a grading logic is imported from `spikes/sscofs-field/certify.py` — never reimplemented. App target gains one resource + one provider type + tests.

**Tech Stack:** `uv run` Python (h5py/fsspec/numpy/pytest), node ≥18 (no new npm deps — the JS artifacts run standalone), Swift/SwiftPM (existing app + TideEngine).

## Global Constraints

- Region bbox −125.5..−122.0 lon, 47.0..50.6 lat. Corpus: 190 days hourly surface u/v ending at build date, nowcast cycles {03,09,15,21} × n001..n006, ranged reads (h5py+fsspec, the spike's verified recipe), shard = `{"t" (s), "u","v" (24,N) f32}` npz, filenames are batch labels — consumers key on `t` only.
- §4a parameters unchanged: D=3 km, scoreable/PASS rules, nearest-scoreable grading — via import from `spikes/sscofs-field/certify.py` (`station_verdicts`, `grade_elements`).
- Shipping-fit survival: certified ∧ node-fit R² ≥ 0.8 both axes. Node fitter parity with FitValidation byte-identical before any batch run (allow only the known non-deterministic `fitMs` field to differ).
- Bundle: format per spec §3 (header JSON sidecar + binary; 3×f32-pair vertices; per-constituent u8 id + f16 amp + f16 phase ×2 axes); **hard size assert ≤ 40 MB in the pack tool**; committed at `Slackwater/Resources/fill-salish.bin` + `fill-salish.json`.
- Provider vends cell polygon + speedKn + bearingDeg at t; no timing semantics; absence = element absent.
- The five-bar station matrix runs on the app's shipping path (FitValidation file mode) exactly as the spike did; samples epoch-MS (`to_sample` contract, chs-glue.js:4).
- Every long-running step is resumable (`.done` markers / existing-file skips) — the pipeline must survive interruption.
- No CHS data in the bundle. No green anywhere. Commit only scripts, docs, and the two bundle resources; corpus/results stay gitignored (`tools/fill-pipeline/.gitignore`).

## File Structure

```
tools/fill-pipeline/
  README.md            # T7: end-to-end reproduce doc
  region_mesh.py       # T1 → data/mesh.json (elements: i, lonc, latc, verts[3][2])
  fetch_region.py      # T1 → data/corpus/*.npz  (parameterized fetch, 190 d, region N)
  stations.py          # T2 → data/stations.json (region-wide truth + axes)
  make_matrix.py       # T2 → data/samples/…, data/index.json (station-adjacent samples, epoch-ms)
  run_matrix.sh        # T2 → data/verdicts/*.json (FitValidation file mode)
  fit_batch.mjs        # T3 → data/fits/*.jsonl  (node shipping fits, u+v per element)
  parity_check.sh      # T3 gate
  survivors.py         # T4 → data/survivors.json (§4a import + R² floor on node fits)
  pack.py              # T5 → Slackwater/Resources/fill-salish.{bin,json} (+ size assert)
  test_pack.py         # T5 round-trip unit tests
Slackwater/…/FillField.swift        # T6 provider
SlackwaterTests/FillFieldTests.swift # T6
```

---

### Task 1: Region mesh + corpus fetcher (kickoff)

**Files:** Create `tools/fill-pipeline/region_mesh.py`, `tools/fill-pipeline/fetch_region.py`, `tools/fill-pipeline/.gitignore` (`data/`, `__pycache__/`, `*.log`).

**Interfaces:**
- `data/mesh.json`: `{"file", "bbox": [-125.5,47.0,-122.0,50.6], "elements": [{"i", "lon", "lat", "verts": [[lon,lat]×3]}]}` — `i` 0-based full-mesh element index; verts from the fields file's `nv` connectivity (1-based node indices → node `lon`/`lat` arrays; verify orientation/off-by-one by asserting each element's centroid ≈ (lonc,latc) within 100 m for a 1000-element sample).
- `data/corpus/YYYYMMDD.npz` exactly as the spike's shards but N = region element count. `fetch_region.py DAYS` resumable, ≥20/24-hour gate, 5 workers.

Steps: adapt from `spikes/sscofs-field/{mesh_subset,fetch_corpus}.py` (state provenance in a header comment; do NOT import them — these two legitimately fork because bbox/verts differ, the §4a-grading no-fork rule applies to certify only). Self-check in region_mesh: element count printed; centroid-vs-verts assertion; nearest-element sanity at Seymour Narrows (50.1333, −125.3500) and Tacoma Narrows (47.2690, −122.5510) < 600 m. Run `./region_mesh.py`; run `./fetch_region.py 2` and verify time mapping still holds (Times variable vs c−6+n) since the region slice changes nothing about time; commit; the controller launches the full 190-day fetch.

- [ ] Steps: write both → run region_mesh (asserts green) → 2-day fetch verify → commit `fill-pipeline: region mesh (with vertices) + parameterized 190d corpus fetcher`

### Task 2: Region-wide truth, samples, matrix

**Files:** Create `stations.py`, `make_matrix.py`, `run_matrix.sh` in `tools/fill-pipeline/`.

**Interfaces:**
- `data/stations.json`: same schema as the spike's `truth/stations.json` (slug/source/id/iwlsId?/lat/lon/flood/ebb) but region-wide; dedup + slug-uniqueness assert carried over.
- `data/index.json` + `data/samples/` + `data/events/`: the spike's `make_samples.py` contract (epoch-MS samples via a `to_sample` equivalent — import it from `spikes/sscofs-field/make_samples.py` to keep one implementation), elements within 600 m, resumable, incremental index.
- `data/verdicts/<slug>-e<i>.json`: FitValidation file-mode 210d-report JSONs (the run_matrix.sh pattern with the stale-report `rm -f` fix).

Steps: adapt (provenance comments); expect ~150–250 stations region-wide — print counts by source; matrix likely 5–10k pairs, hours — resumable, run by controller in background. Unit-test only what's new (none expected — this is parameterization; if you write new logic, test it). Commit `fill-pipeline: region truth stations + shipping-path station matrix`.

- [ ] Steps: write → stations.py real run (counts + asserts) → make_matrix smoke on the partial corpus then clean → commit (controller runs full matrix when corpus lands)

### Task 3: Node batch fitter + parity gate

**Files:** Create `fit_batch.mjs`, `parity_check.sh` in `tools/fill-pipeline/`.

**Interfaces:**
- `node fit_batch.mjs <corpus-dir> <survivor-candidates.json> <out-dir>` — loads `Slackwater/Resources/chs-bundle.js` + `chs-glue.js` in a vm context (node-control.mjs precedent), per element: build `[{t: epochMs, v: kn}]` for u and for v from the npz shards — npz reading in node: DON'T. Python exports per-element sample files? 300k elements × 2 = too many files. Instead `fit_batch.mjs` reads a compact intermediate: `survivors.py` (T4) writes candidate u/v series as one binary f32 blob + index (documented in-file); OR simpler: Python driver `fit_drive.py` streams series into fit_batch.mjs via stdin JSONL ({elem, axis, samples:[...]}) and collects stdout JSONL ({elem, axis, constituents, offset, r2}). Choose the stdin/stdout pipe — no intermediate blob format to design. fit_batch.mjs is then a pure filter; resumability lives in the Python driver (skip elems present in out JSONL).
- `parity_check.sh`: feeds a saved FitValidation samples file (any cached `*-210d-samples.json` from the matrix run) through fit_batch.mjs and diffs constituents JSON against FitValidation's `-fit.json` for the same window — byte-identical modulo `fitMs`. Non-identical = exit 1; wire it as the first line of any batch invocation.

R² per axis computed in the driver from the fit's residuals (predict via the returned constituents at sample times — chs-glue exposes prediction? if not, evaluate cos-sum in Python from constituents; document which). Commit `fill-pipeline: node shipping-fitter batch (stdin JSONL) + FitValidation parity gate`.

- [ ] Steps: write → parity gate green against a real cached fit → tiny smoke batch (5 elements from the spike's box corpus) → commit

### Task 4: Survivors — §4a region-wide + shipping-fit floor

**Files:** Create `survivors.py` in `tools/fill-pipeline/`.

**Interfaces:**
- Imports `station_verdicts`, `grade_elements` from `spikes/sscofs-field/certify.py` (sys.path insert; a comment marks the single-implementation rule).
- Stage 1: verdicts from `data/verdicts/` + `data/index.json` → grade all region elements → certified set (+ counts at D=2/3/5 km recorded).
- Stage 2: numpy prefilter (reuse the vectorized lstsq from `spikes/sscofs-field/prune_proof.py` — import its `design_matrix`/`fit_elements` if importable, else adapt with provenance) → shortlist certified ∧ prefilter-R² ≥ 0.7 (loose on purpose; final floor is the node fit).
- Stage 3: drive T3's fitter over the shortlist → `data/fits/fits.jsonl`; final survivors = node-fit R² ≥ 0.8 both axes → `data/survivors.json` `{"D_m", "counts": {...}, "elements": [{"i", "constituents_u": [...], "constituents_v": [...], "r2_u", "r2_v"}]}`.

Report in stdout + `data/SURVIVORS.md`: station verdict counts, certified %, prefilter shortlist size, node-fit survivor count, and the sanity anchor — Seymour Narrows neighbourhood must be MASKED if its station fails speed-only region-wide, certified if it passes (report which; do not assume). Commit `fill-pipeline: region survivors — §4a grading + shipping-fit R² floor`.

- [ ] Steps: write (tests only for new glue logic; grading/fit logic is imported) → run over real data when T2 matrix + corpus complete → commit

### Task 5: Pack tool + bundle

**Files:** Create `pack.py`, `test_pack.py` in `tools/fill-pipeline/`; commit generated `Slackwater/Resources/fill-salish.bin` + `fill-salish.json`.

**Interfaces:**
- Binary layout (little-endian): per element — u8 vert-count (=3) then 3×(f32 lon, f32 lat); u8 nu (kept u-constituents) then nu×(u8 id, f16 amp, f16 phase); u8 nv then same for v. Elements concatenated; element count + byte offsets table in the JSON header (or a fixed-stride offsets array at file head — pick one, document in header `format_version: 1`).
- Header JSON: format_version, region tag, bbox, corpus window (ISO), mesh source URL + sha256 of mesh.json, D_m, floors, station-set sha256, generated (ISO), element_count, constituent id table (id → name), bin sha256.
- Energy floor at pack time (per-axis max(2%, 0.005 kn), §10 semantics as amended) — the fits carry all constituents; pack prunes.
- **`assert size <= 40*1024*1024`** with a clear message.
- `test_pack.py`: round-trip (pack synthetic 3-element input → parse with a tiny pure-python reader in the test → constants/verts equal within f16 tolerance); size-assert fires on an artificially fat input.

Commit `fill-pipeline: bundle pack tool + fill-salish resource` (bundle committed only when generated from the real survivor set).

- [ ] Steps: TDD round-trip → implement → real pack → commit incl. resources

### Task 6: Swift FillField provider

**Files:** Create the provider in the app target (follow existing structure — find where `CurrentStation`/station providers live and match; likely `Slackwater/…`), tests in the existing test target.

**Interfaces:**
- `struct FillCell { let polygon: [CLLocationCoordinate2D]; let speedKn: Double; let bearingDeg: Double }`
- `final class FillField { init?(resource: String = "fill-salish"); func cells(at date: Date, in bbox: MapBBox?) -> [FillCell] }` — adapt naming/types to the codebase's existing conventions (read neighbours first; the seam consumer is the #57 session's layer, so keep the payload exactly polygon+speed+bearing, evaluate-at-t).
- Evaluation: reconstruct u,v per element via TideEngine's constituent evaluation (`HarmonicConstituent` init with name/amplitude/phase exists — FitValidation uses it); speed = hypot, bearing = atan2(u,v) deg true. If TideEngine's evaluator needs a station wrapper, evaluate the cos-sum directly in FillField — smallest diff wins, but the astronomical arguments (V₀+u, f) MUST come from TideEngine/engine machinery, never re-derived.
- Tests: bundle load (real committed resource: element_count matches header); synthetic golden (hand-built 1-element bundle fixture, M2-only, assert speed at two instants against a hand-computed value); real golden (one element id + fixed date → speed, pinned with a tolerance and a comment on provenance).

Commit `app: FillField provider — fill bundle loader + evaluate-at-t seam payload`. Run the existing app test suite — must stay green.

- [ ] Steps: read neighbours → TDD synthetic golden → implement → real golden → full suite → commit

### Task 7: Docs + PR

- `tools/fill-pipeline/README.md`: end-to-end reproduce (each stage, its cost, resume semantics), the survivor/certification stats from the real run, bundle stats (MB, elements, mean constituents).
- Spec status block: Phase B delivered state; composite spec §2 marker → delivered-for-fill pointer.
- `spikes/sscofs-field/README.md`: one-line addendum pointing at the production pipeline.
- Push, `gh pr create` (internal): summary with the real numbers, refs #99/#57. Standard PR footer.

- [ ] Steps: write → verify doc claims against artifacts → commit `docs: fill pipeline + Phase B delivery record` → push → PR

## Self-review notes
- One-implementation rules: §4a grading imported (T4); `to_sample` imported (T2); shipping fitter = committed JS artifacts (T3); astronomical arguments from the engine (T6). Forks limited to mesh/fetch parameterization, marked with provenance.
- Long steps all resumable; controller owns the two long background runs (corpus, matrix).
- The bundle commits only after the size assert passes on real data; no green, no timing anywhere in the payload.
