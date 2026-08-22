# Grown Patches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship bounded per-pass current fields grown from validated gate harmonics into the throats the mesh can't resolve — per `docs/superpowers/specs/2026-08-21-grown-patches-design.md`.

**Architecture:** A Python pipeline (`tools/patch-pipeline/`, sibling of `tools/fill-pipeline/`) turns bathymetry tiles + hand-authored channel inputs into committed per-pass cross-section artifacts (`passes/<slug>.json`), certifies the scaling method against in-channel NOAA check stations using the existing FitValidation bars, and packs surviving sections into one `patches-salish.bin`. A Swift `PatchField` (mirroring `FillField`) evaluates each patch's anchor harmonic at t and multiplies per-cell scales, vending ordinary `FillCell`s plus channel-2 oriented samples.

**Tech Stack:** Python (uv scripts, numpy + rasterio for tiles), the existing FitValidation Swift CLI, Swift/TideEngine on the app side.

## Global Constraints

- **Sequencing is the spec's go/no-go:** Task 4 (method certification at Tacoma + Deception) must PASS on the existing M47 bars before any BC task (8–9) runs. On FAIL: stop, report to owner — the fallback is composite §7's Discovery-FVCOM conversation, never a loosened bar.
- **Licence:** raw NONNA/BlueTopo tiles live only under gitignored `tools/patch-pipeline/data/` — never committed, never bundled. Committed artifacts are derived cross-sections only. The CHS NONNA verbatim notice ships in the same change as the first BC patch (Task 9).
- **Absence stays absence; no green; no timing in the fill family; patch outranks backdrop by draw order; shrink, never smooth.** (Spec header rulings — nothing in this plan re-decides them.)
- Binary format family: little-endian, f32 vertices, f16 payloads, sidecar JSON with offsets — mirror `tools/fill-pipeline/pack.py` / `Slackwater/FillField.swift`.
- Swift files carry the `// Slackwater — GPL v3.` header-comment style; Python tools use `#!/usr/bin/env -S uv run --script --with <deps>` like the fill pipeline.
- Work in a git worktree branched off origin/main; branch-and-PR (shared repo — never commit to main, never merge your own PR). Commit after every task's green step.
- TDD throughout: failing test first, minimal code, green, commit.

## File Structure

```
tools/patch-pipeline/
  README.md                  # runbook: tile acquisition, run order, drift check
  .gitignore                 # data/
  sections.py                # inputs/<slug>.json + tiles -> passes/<slug>.json
  sensitivity.py             # perturbation sweep -> kept_range truncation
  certify_patch.py           # patch-predicted samples + truth events for check stations
  run_certify.sh             # FitValidation loop (fork of fill-pipeline/run_matrix.sh)
  pack.py                    # passes/*.json -> Slackwater/Resources/patches-salish.bin + .json
  test_sections.py
  test_pack.py
  inputs/<slug>.json         # hand-authored per pass (committed)
  passes/<slug>.json         # derived, licence-clean (committed)
  passes/CERTIFICATION.md    # method-certification + per-patch verdicts (committed)
  data/                      # gitignored: tiles/<slug>/*, samples/, events/, verdicts/
Slackwater/PatchField.swift  # PatchField + PatchSample (FillCell reused)
Slackwater/FillField.swift   # one-word change: FillByteReader private -> internal
Slackwater/SettingsView.swift# NONNA notice (Task 9)
SlackwaterTests/PatchFieldTests.swift
Slackwater/Resources/patches-salish.bin + patches-salish.json
```

### Canonical `passes/<slug>.json` schema (produced by Task 1, consumed by 3/5/6)

```json
{
  "slug": "tacoma-narrows",
  "generated": "2026-08-22T00:00:00Z",
  "anchor": {"provider": "noaa", "station_id": "PUG1527", "lat": 47.27432,
             "lon": -122.54532, "flood_deg": 11.0, "spring_max_kn": 5.0,
             "section_index": 12},
  "datum": {"reference": "MWL", "cd_to_mwl_m": 2.0},
  "section_spacing_m": 150,
  "thalweg": [[-122.545, 47.26], [-122.546, 47.262]],
  "sections": [{"center": [-122.545, 47.26], "bearing_deg": 11.0,
                "width_m": 1400.0, "area_m2": 52000.0,
                "left": [-122.552, 47.259], "right": [-122.538, 47.261]}],
  "scales": [1.18],
  "kept_range": [0, 24],
  "ends": {"start": "~1 channel-width past N mouth (Point Evans)",
           "end": "junction with Hale Passage"},
  "provenance": {"tiles": [{"file": "BlueTopo_BH4PS58C_20250601.tiff",
                            "source_url": "https://...", "sha256": "...",
                            "retrieved": "2026-08-22", "contributor": "checked: NOAA OCS, CC0"}],
                 "inputs_sha256": "..."}
}
```

`bearing_deg` is the **flood** set direction (thalweg seed is drawn in the flood direction; asserted against `anchor.flood_deg` ±60°). `scales[i] = area(anchor section) / area(section i)`. `kept_range` is inclusive section indices; `sections.py` writes the full range, `sensitivity.py` narrows it.

---

### Task 1: `sections.py` — cross-section geometry on synthetic bathymetry

**Files:**
- Create: `tools/patch-pipeline/README.md`, `tools/patch-pipeline/.gitignore`, `tools/patch-pipeline/sections.py`, `tools/patch-pipeline/test_sections.py`

**Interfaces:**
- Consumes: `tools/patch-pipeline/inputs/<slug>.json` (schema below) + GeoTIFF tiles under `data/tiles/<slug>/` with a `MANIFEST.json` beside them.
- Produces: `passes/<slug>.json` per the canonical schema above; `build_pass(inputs: dict, depth_at: Callable[[float, float], float]) -> dict` as the testable core (depth in metres at MWL, positive down, NaN = land/nodata).

Input schema (`inputs/<slug>.json`, hand-authored, committed):

```json
{
  "slug": "tacoma-narrows",
  "anchor": {"provider": "noaa", "station_id": "PUG1527", "lat": 47.27432,
             "lon": -122.54532, "flood_deg": 11.0, "spring_max_kn": 5.0},
  "thalweg_seed": [[-122.5560, 47.3050], [-122.5480, 47.2900], [-122.5450, 47.2740], [-122.5560, 47.2620]],
  "section_spacing_m": 150,
  "max_half_width_m": 1500,
  "cd_to_mwl_m": 2.0,
  "tile_value": "elevation",
  "ends": {"start": "...", "end": "..."},
  "check_stations": [{"station_id": "PUG1524", "lat": 47.30600, "lon": -122.55003,
                      "flood_deg": 341.0, "ebb_deg": 170.0}]
}
```

`tile_value` is `"elevation"` (BlueTopo: metres, negative down) or `"depth"` (NONNA: metres, positive down). Depth at MWL = (depth-sign value) + `cd_to_mwl_m`.

- [ ] **Step 1: Write the failing test** — synthetic V-shaped channel with analytically known areas.

```python
# tools/patch-pipeline/test_sections.py — run: uv run --with pytest,numpy pytest -q test_sections.py
import math
import numpy as np
from sections import build_pass

M_PER_DEG_LAT = 111320.0

def synthetic_inputs():
    # Straight north-south channel at lon 0, 2000 m wide, depth profile
    # parabolic across, deepening linearly northward: analytic areas.
    return {
        "slug": "synthetic",
        "anchor": {"provider": "noaa", "station_id": "TEST1", "lat": 0.0, "lon": 0.0,
                   "flood_deg": 0.0, "spring_max_kn": 4.0},
        "thalweg_seed": [[0.0002, -0.009], [-0.0002, 0.009]],  # slightly off-center: refine must recenter
        "section_spacing_m": 500,
        "max_half_width_m": 2000,
        "cd_to_mwl_m": 0.0,
        "tile_value": "depth",
        "ends": {"start": "test", "end": "test"},
        "check_stations": [],
    }

def synthetic_depth(lon, lat):
    # Channel: |x| <= 1000 m water, parabolic depth, max at x=0 growing north.
    x = lon * M_PER_DEG_LAT  # cos(0)=1
    y = lat * M_PER_DEG_LAT
    if abs(x) > 1000:
        return float("nan")
    dmax = 50.0 + y * 0.001  # 50 m at y=0, +1 m per km north
    return dmax * (1 - (x / 1000.0) ** 2)

def test_areas_match_analytic():
    out = build_pass(synthetic_inputs(), synthetic_depth)
    # Parabolic profile: A = (2/3) * width * dmax
    for sec in out["sections"]:
        y = sec["center"][1] * M_PER_DEG_LAT
        expect = (2.0 / 3.0) * 2000.0 * (50.0 + y * 0.001)
        assert abs(sec["area_m2"] - expect) / expect < 0.05

def test_thalweg_refined_to_deepest():
    out = build_pass(synthetic_inputs(), synthetic_depth)
    for pt in out["thalweg"]:
        assert abs(pt[0] * M_PER_DEG_LAT) < 60  # snapped to centerline within sample step

def test_scales_anchor_identity():
    out = build_pass(synthetic_inputs(), synthetic_depth)
    k = out["anchor"]["section_index"]
    assert out["scales"][k] == 1.0
    # deeper north sections -> larger area -> scale < 1 north of anchor
    assert out["scales"][-1] < 1.0 or out["scales"][0] < 1.0

def test_flood_bearing_assert():
    bad = synthetic_inputs()
    bad["anchor"]["flood_deg"] = 180.0  # seed drawn south->north = flood 0; reversed must raise
    try:
        build_pass(bad, synthetic_depth)
        assert False, "expected SystemExit on reversed thalweg"
    except SystemExit:
        pass
```

- [ ] **Step 2: Run to verify failure** — `cd tools/patch-pipeline && uv run --with pytest,numpy pytest -q test_sections.py` → FAIL (`sections` not found).

- [ ] **Step 3: Implement `sections.py`.**

```python
#!/usr/bin/env -S uv run --script --with numpy,rasterio
"""Slackwater patch-pipeline — cross-section derivation (grown-patches spec §2).

inputs/<slug>.json + bathymetry tiles (data/tiles/<slug>/, gitignored, with
MANIFEST.json) -> passes/<slug>.json: refined thalweg, perpendicular sections,
A(x) at MWL, continuity scales A(anchor)/A(x).

Thalweg refinement = "deepest connected path", operationally: build sections
perpendicular to the hand-drawn seed, recenter each on its deepest sample,
rebuild sections perpendicular to the refined polyline once. The sensitivity
sweep (sensitivity.py) owns placement-error truncation.

Licence: tiles are never committed (NONNA clause 7 / BlueTopo per-tile
contributor check); this file copies MANIFEST provenance into the committed
pass artifact so the tile cache is disposable.
"""
import hashlib, json, math, os, sys
from datetime import datetime, timezone

import numpy as np

M_PER_DEG_LAT = 111320.0
CROSS_STEP_M = 10.0  # depth-sample step across a section


def _m_per_deg_lon(lat):
    return M_PER_DEG_LAT * math.cos(math.radians(lat))


def _bearing_deg(p0, p1):
    """Initial bearing p0->p1, degrees true, flat-earth (passes are km-scale)."""
    dx = (p1[0] - p0[0]) * _m_per_deg_lon(p0[1])
    dy = (p1[1] - p0[1]) * M_PER_DEG_LAT
    return math.degrees(math.atan2(dx, dy)) % 360


def _walk(points, spacing_m):
    """Resample a polyline to ~spacing_m station points (lon/lat)."""
    out = [points[0]]
    carry = 0.0
    for p0, p1 in zip(points, points[1:]):
        seg = math.hypot((p1[0] - p0[0]) * _m_per_deg_lon(p0[1]),
                         (p1[1] - p0[1]) * M_PER_DEG_LAT)
        d = carry
        while d + spacing_m <= seg:
            d += spacing_m
            f = d / seg
            out.append([p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f])
        carry = (d + spacing_m) - seg - spacing_m  # distance already walked into next seg
        carry = max(carry, 0.0)
    return out


def _section(center, bearing_deg, half_width_m, depth_at):
    """Sample depth across the channel perpendicular to bearing.
    Returns (left, right, width_m, area_m2, deepest_point) or None if dry."""
    perp = math.radians(bearing_deg + 90.0)
    ux = math.sin(perp) / _m_per_deg_lon(center[1])
    uy = math.cos(perp) / M_PER_DEG_LAT
    offsets = np.arange(-half_width_m, half_width_m + CROSS_STEP_M, CROSS_STEP_M)
    pts = [[center[0] + ux * o, center[1] + uy * o] for o in offsets]
    depths = np.array([depth_at(p[0], p[1]) for p in pts])
    wet = np.isfinite(depths) & (depths > 0)
    if not wet.any():
        return None
    # contiguous wet run containing the channel: take the run containing the
    # deepest sample (side embayments/other channels excluded by construction)
    dpi = int(np.nanargmax(np.where(wet, depths, -np.inf)))
    lo = dpi
    while lo > 0 and wet[lo - 1]:
        lo -= 1
    hi = dpi
    while hi < len(wet) - 1 and wet[hi + 1]:
        hi += 1
    area = float(np.trapz(depths[lo:hi + 1], dx=CROSS_STEP_M))
    width = float((hi - lo) * CROSS_STEP_M)
    return pts[lo], pts[hi], width, area, pts[dpi]


def build_pass(inputs, depth_at):
    """Pure core: inputs dict + depth_at(lon, lat)->metres-at-MWL (NaN=dry)."""
    spacing = inputs["section_spacing_m"]
    half_w = inputs["max_half_width_m"]

    # pass 1: sections on the seed, recenter on deepest point
    seed = _walk(inputs["thalweg_seed"], spacing)
    refined = []
    for i, c in enumerate(seed):
        nb = seed[max(i - 1, 0)], seed[min(i + 1, len(seed) - 1)]
        b = _bearing_deg(*nb)
        s = _section(c, b, half_w, depth_at)
        if s:
            refined.append(s[4])
    if len(refined) < 3:
        raise SystemExit(f"{inputs['slug']}: <3 wet sections — check tiles/inputs")

    # pass 2: sections perpendicular to the refined thalweg
    stations = _walk(refined, spacing)
    sections = []
    for i, c in enumerate(stations):
        nb = stations[max(i - 1, 0)], stations[min(i + 1, len(stations) - 1)]
        b = _bearing_deg(*nb)
        s = _section(c, b, half_w, depth_at)
        if s is None:
            continue
        left, right, width, area, _ = s
        sections.append({"center": [float(c[0]), float(c[1])], "bearing_deg": round(b, 1),
                         "width_m": round(width, 1), "area_m2": round(area, 1),
                         "left": [float(left[0]), float(left[1])],
                         "right": [float(right[0]), float(right[1])]})

    # anchor section = nearest to the anchor station; flood-orientation assert
    a = inputs["anchor"]
    dists = [math.hypot((s["center"][0] - a["lon"]) * _m_per_deg_lon(a["lat"]),
                        (s["center"][1] - a["lat"]) * M_PER_DEG_LAT) for s in sections]
    k = int(np.argmin(dists))
    diff = abs((sections[k]["bearing_deg"] - a["flood_deg"] + 180) % 360 - 180)
    if diff > 60:
        raise SystemExit(f"{inputs['slug']}: thalweg bearing {sections[k]['bearing_deg']} vs "
                         f"anchor flood {a['flood_deg']} — seed must be drawn in the flood direction")

    a_area = sections[k]["area_m2"]
    scales = [round(a_area / s["area_m2"], 4) for s in sections]
    return {
        "slug": inputs["slug"],
        "anchor": {**a, "section_index": k},
        "datum": {"reference": "MWL", "cd_to_mwl_m": inputs["cd_to_mwl_m"]},
        "section_spacing_m": spacing,
        "thalweg": [[float(p[0]), float(p[1])] for p in refined],
        "sections": sections,
        "scales": scales,
        "kept_range": [0, len(sections) - 1],
        "ends": inputs["ends"],
    }


def tile_depth_fn(tile_dir, tile_value, cd_to_mwl_m):
    """depth_at(lon, lat) over every GeoTIFF in tile_dir (WGS84-warped read)."""
    import rasterio
    from rasterio.warp import transform as rio_transform
    from rasterio.crs import CRS
    srcs = [rasterio.open(os.path.join(tile_dir, f))
            for f in sorted(os.listdir(tile_dir)) if f.lower().endswith((".tif", ".tiff"))]
    if not srcs:
        raise SystemExit(f"no GeoTIFFs in {tile_dir}")
    wgs = CRS.from_epsg(4326)

    def depth_at(lon, lat):
        for src in srcs:
            xs, ys = rio_transform(wgs, src.crs, [lon], [lat])
            row, col = src.index(xs[0], ys[0])
            if 0 <= row < src.height and 0 <= col < src.width:
                v = src.read(1, window=((row, row + 1), (col, col + 1)))[0, 0]
                if src.nodata is not None and v == src.nodata:
                    return float("nan")
                d = -float(v) if tile_value == "elevation" else float(v)
                return d + cd_to_mwl_m
        return float("nan")
    return depth_at


def main(slug):
    inputs = json.load(open(f"inputs/{slug}.json"))
    tile_dir = f"data/tiles/{slug}"
    manifest = json.load(open(os.path.join(tile_dir, "MANIFEST.json")))
    for t in manifest["tiles"]:  # verify cache integrity before deriving anything
        got = hashlib.sha256(open(os.path.join(tile_dir, t["file"]), "rb").read()).hexdigest()
        if got != t["sha256"]:
            raise SystemExit(f"{t['file']}: sha256 mismatch — re-download, or update MANIFEST deliberately")
    depth_at = tile_depth_fn(tile_dir, inputs["tile_value"], inputs["cd_to_mwl_m"])
    out = build_pass(inputs, depth_at)
    out["generated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out["provenance"] = {"tiles": manifest["tiles"],
                         "inputs_sha256": hashlib.sha256(open(f"inputs/{slug}.json", "rb").read()).hexdigest()}
    os.makedirs("passes", exist_ok=True)
    json.dump(out, open(f"passes/{slug}.json", "w"), indent=1)
    print(f"{slug}: {len(out['sections'])} sections, anchor at index {out['anchor']['section_index']}, "
          f"scale range {min(out['scales'])}-{max(out['scales'])}")


if __name__ == "__main__":
    main(sys.argv[1])
```

`MANIFEST.json` shape (hand-written when downloading tiles):

```json
{"tiles": [{"file": "<name>.tiff", "source_url": "https://...", "sha256": "<sha256 of file>",
            "retrieved": "2026-08-22", "contributor": "checked: <band-2 contributor / licence note>"}]}
```

- [ ] **Step 4: Run tests** — `uv run --with pytest,numpy pytest -q test_sections.py` → PASS. Fix geometry until the analytic-area test holds; the tolerance is 5 %.

- [ ] **Step 5: Write `README.md` + `.gitignore`.** `.gitignore` contains `data/`. README records: what the pipeline produces, tile acquisition (BlueTopo: browse the tile index at `https://noaa-ocs-nationalbathymetry-pds.s3.amazonaws.com/index.html#BlueTopo/`, download the tile(s) covering each pass bbox, record band-2 contributor check in MANIFEST; NONNA: register at the CHS NONNA portal `https://data.chs-shc.ca`, accept the licence, download NONNA-10 GeoTIFF tiles for the pass, note licence acceptance date in MANIFEST), run order (`sections.py <slug>` → `sensitivity.py <slug>` → `certify_patch.py` → `pack.py`), and the drift check (re-run `sections.py`, `git diff passes/` must be empty apart from `generated`).

- [ ] **Step 6: Commit** — `git add tools/patch-pipeline && git commit -m "patch-pipeline: cross-section derivation core (sections.py) with analytic-channel tests"`

---

### Task 2: Tacoma + Deception real inputs and pass artifacts

**Files:**
- Create: `tools/patch-pipeline/inputs/tacoma-narrows.json`, `tools/patch-pipeline/inputs/deception-pass.json`, `tools/patch-pipeline/passes/tacoma-narrows.json`, `tools/patch-pipeline/passes/deception-pass.json`
- Data (gitignored): `tools/patch-pipeline/data/tiles/{tacoma-narrows,deception-pass}/` + `MANIFEST.json`

**Interfaces:**
- Consumes: `sections.py` from Task 1.
- Produces: two committed `passes/<slug>.json` artifacts + a review plot per pass (PNG under `data/`, attached to the PR — the owner's §6b.4 bounds review evidence).

- [ ] **Step 1: Author `inputs/tacoma-narrows.json`.** Anchor `PUG1527` (0.3 mi N of bridge). Pull anchor/check metadata from the app bundle: `jq '.[] | select(.id=="PUG1527" or .id=="PUG1524" or .id=="PUG1526" or .id=="PUG1528") | {id, latitude, longitude, floodDirection, ebbDirection}' Slackwater/Resources/currents.json`. `spring_max_kn`: max `Velocity_Major` over a spring week from the CO-OPS predictions API (same endpoint as Task 3's fetcher). Thalweg seed: 8–12 points traced down the channel from the BlueTopo tile rendered with rasterio (`data/` scratch plot) — **drawn in the flood direction** (flood sets N at Tacoma: seed runs S→N). Ends per spec: ~1 channel-width past each mouth (N: past Point Evans toward Dalco Passage junction; S: before the Hale Passage junction) — write the reason strings into `ends`. `check_stations`: PUG1524, PUG1526, PUG1528. `cd_to_mwl_m`: MLLW→MSL offset for Tacoma from NOAA datums (`https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/9446484/datums.json`, MSL−MLLW); `tile_value: "elevation"`.

- [ ] **Step 2: Same for `inputs/deception-pass.json`.** Anchor `PUG1701`; check station `PUG1629` (Yokeko Point). Flood sets E through the pass: seed runs W→E. Ends: W mouth ~1 width into Rosario side; E end past Yokeko toward the Similk Bay opening (junction). Datum station: Seattle-area reference near the pass (`9448558` Cornet Bay if it has datums, else nearest with MSL−MLLW).

- [ ] **Step 3: Download BlueTopo tiles for both passes into `data/tiles/<slug>/`, write `MANIFEST.json`** (sha256 via `shasum -a 256`; open each tile's band 2 contributor table with rasterio and record the check — spec requires the per-tile CC0 confirmation).

- [ ] **Step 4: Run `sections.py tacoma-narrows` and `sections.py deception-pass`.** Both must complete with anchor-identity scale 1.0 and no flood-bearing assert. Eyeball guard: Tacoma throat width ~1.4 km, Deception narrows width ~200 m — if a computed `width_m` is wildly off, the wet-run extraction grabbed the wrong channel; fix the seed or `max_half_width_m`.

- [ ] **Step 5: Render one review plot per pass** (scratch script, `data/plot-<slug>.png`): tile hillshade + channel sections + thalweg + anchor/check stations. These go into the PR body for the owner's bounds review.

- [ ] **Step 6: Commit** — `git add tools/patch-pipeline/inputs tools/patch-pipeline/passes && git commit -m "patch-pipeline: Tacoma Narrows + Deception Pass inputs and derived cross-sections"`

---

### Task 3: `certify_patch.py` + `run_certify.sh` — method-certification harness

**Files:**
- Create: `tools/patch-pipeline/certify_patch.py`, `tools/patch-pipeline/run_certify.sh`
- Test: extend `tools/patch-pipeline/test_sections.py` (sample-generation unit lives beside it: `test_certify_samples` — one file per pipeline concern is fill-pipeline's convention, but the certify unit is small; keep it in a new `test_certify.py`)

**Interfaces:**
- Consumes: `passes/<slug>.json` (Task 2); NOAA CO-OPS predictions API; `tools/FitValidation` CLI (`swift run -c release fit-validation --samples --events --flood --ebb --label`); sample/event JSON shapes from `tools/fill-pipeline/make_matrix.py` (`to_sample` → `{t: epoch-ms, v: signed kn}`; events `[{eventDate, qualifier, value}]`).
- Produces: `data/certify/index.json` rows `{slug, samples, events, flood, ebb}` (label = slug); `data/verdicts/<label>.{json,log,status}`; `passes/CERTIFICATION.md`.

Method: for each check station, the patch's prediction there is the **anchor's own published prediction series × scale(check station's nearest section)**, signed (flood→flood carries sign). Truth is the check station's published MAX_SLACK events. FitValidation fits its 210-day model from the scaled samples and grades events — the same M47 bars that admitted every shipping gate, one implementation, never a fork. (The runtime path evaluates bundled constituents instead of the CO-OPS series; the Task 7 golden test covers that equivalence at the anchor.)

- [ ] **Step 1: Write the failing test.**

```python
# tools/patch-pipeline/test_certify.py — uv run --with pytest,numpy,requests pytest -q test_certify.py
import json
from certify_patch import nearest_scale, scale_samples

PASS_DOC = {
    "sections": [{"center": [0.0, 0.0]}, {"center": [0.0, 0.01]}, {"center": [0.0, 0.02]}],
    "scales": [1.0, 0.5, 0.25],
    "kept_range": [0, 2],
}

def test_nearest_scale_picks_closest_section():
    assert nearest_scale(PASS_DOC, lat=0.011, lon=0.0) == 0.5

def test_nearest_scale_refuses_outside_kept_range():
    doc = dict(PASS_DOC, kept_range=[0, 1])
    try:
        nearest_scale(doc, lat=0.02, lon=0.0)
        assert False, "check station outside kept_range must be a hard error"
    except SystemExit:
        pass

def test_scale_samples_preserves_sign_and_time():
    samples = [{"t": 1000, "v": 2.0}, {"t": 2000, "v": -1.0}]
    out = scale_samples(samples, 0.5)
    assert out == [{"t": 1000, "v": 1.0}, {"t": 2000, "v": -0.5}]
```

- [ ] **Step 2: Run to verify failure** — `uv run --with pytest,numpy,requests pytest -q test_certify.py` → FAIL.

- [ ] **Step 3: Implement `certify_patch.py`.**

```python
#!/usr/bin/env -S uv run --script --with numpy,requests
"""Slackwater patch-pipeline — method certification (grown-patches spec §6a).

For every check station of every pass with one: samples = the anchor's own
CO-OPS prediction series x scale(check section), signed; events = the check
station's published MAX_SLACK truth. run_certify.sh then grades each pair
with tools/FitValidation — the M47 bars, one implementation, never a fork.

Anchor series via CO-OPS `currents_predictions` interval=6 (Velocity_Major,
signed kn on the anchor's flood axis), fetched in ~30-day chunks over the
same 190-day style window the fill corpus used. Event fetch idiom is
make_matrix.py's noaa_events, reused by import.
"""
import json, math, os, sys, datetime as dt

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "fill-pipeline"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "spikes", "sscofs-field"))
from make_samples import to_sample          # one epoch-ms sample rule in the repo
from make_matrix import noaa_events, CP     # one NOAA event idiom
import requests

M_PER_DEG_LAT = 111320.0
FIT_DAYS = 190
VAL_OFFSET_DAYS, VAL_LEN_DAYS = 28, 7       # mirror make_matrix's held-out window


def nearest_scale(pass_doc, lat, lon):
    lo, hi = pass_doc["kept_range"]
    best, best_d = None, float("inf")
    for i in range(lo, hi + 1):
        c = pass_doc["sections"][i]["center"]
        d = math.hypot((c[0] - lon) * M_PER_DEG_LAT * math.cos(math.radians(lat)),
                       (c[1] - lat) * M_PER_DEG_LAT)
        if d < best_d:
            best, best_d = i, d
    if best is None or best_d > pass_doc.get("section_spacing_m", 150) * 2:
        raise SystemExit(f"check station {lat},{lon} has no section within 2 spacings of kept_range")
    return pass_doc["scales"][best]


def scale_samples(samples, scale):
    return [{"t": s["t"], "v": s["v"] * scale} for s in samples]


def anchor_series(station_id, start, end):
    """Signed Velocity_Major kn, 6-min, chunked ~30 days (API range limit)."""
    out = []
    t0 = start
    while t0 < end:
        t1 = min(t0 + dt.timedelta(days=30), end)
        r = requests.get(CP, params={"station": station_id, "product": "currents_predictions",
                                     "begin_date": f"{t0:%Y%m%d}", "end_date": f"{t1:%Y%m%d}",
                                     "interval": "6", "units": "english",
                                     "time_zone": "gmt", "format": "json"}, timeout=120).json()
        for e in r["current_predictions"]["cp"]:
            ts = dt.datetime.strptime(e["Time"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
            out.append(to_sample(ts.timestamp(), float(e["Velocity_Major"])))
        t0 = t1
    return out


def main():
    end = dt.datetime.now(dt.timezone.utc).replace(minute=0, second=0, microsecond=0)
    start = end - dt.timedelta(days=FIT_DAYS)
    val = (end + dt.timedelta(days=VAL_OFFSET_DAYS), end + dt.timedelta(days=VAL_OFFSET_DAYS + VAL_LEN_DAYS))
    os.makedirs("data/certify/samples", exist_ok=True)
    os.makedirs("data/certify/events", exist_ok=True)
    index = []
    for f in sorted(os.listdir("passes")):
        if not f.endswith(".json"):
            continue
        pass_doc = json.load(open(f"passes/{f}"))
        inputs = json.load(open(f"inputs/{pass_doc['slug']}.json"))
        if not inputs.get("check_stations"):
            continue
        anchor = pass_doc["anchor"]
        base = anchor_series(anchor["station_id"], start, end)
        for ck in inputs["check_stations"]:
            label = f"{pass_doc['slug']}-{ck['station_id']}"
            sp = f"data/certify/samples/{label}.json"
            ep = f"data/certify/events/{label}.json"
            if not (os.path.exists(sp) and os.path.exists(ep)):   # resumable
                s = nearest_scale(pass_doc, ck["lat"], ck["lon"])
                json.dump(scale_samples(base, s), open(sp, "w"))
                json.dump(noaa_events({"id": ck["station_id"]}, *val), open(ep, "w"))
            index.append({"slug": label, "samples": sp, "events": ep,
                          "flood": ck["flood_deg"], "ebb": ck["ebb_deg"]})
            print(label)
    json.dump(index, open("data/certify/index.json", "w"), indent=1)


if __name__ == "__main__":
    main()
```

(`make_matrix.py` has no `if __name__` guard issues for import? It does — its `main()` runs on import if unguarded. Check: it defines `main()` and calls it under a guard at the file end; if the guard is missing, import `noaa_events` by `importlib` loading with `__name__ != "__main__"` still safe only with the guard. **Verify before wiring; if unguarded, copy `noaa_events`/`CP` (9 lines) with a provenance comment instead of importing.**)

- [ ] **Step 4: Implement `run_certify.sh`** — fork of `tools/fill-pipeline/run_matrix.sh` (legit fork per make_matrix precedent: paths + status capture differ, grading tool identical):

```bash
#!/bin/bash
# Grade every patch-vs-check-station pair with tools/FitValidation — the M47
# bars, unmodified. Fork of fill-pipeline/run_matrix.sh (own data dirs, plus
# a .status file capturing the tool's exit code = its own PASS/FAIL verdict).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data/verdicts
REPORTS=/tmp/fit-validation/reports

jq -c '.[]' data/certify/index.json | while read -r row; do
  label=$(jq -r .slug <<<"$row")
  [ -f "data/verdicts/${label}.done" ] && continue
  report="${REPORTS}/${label}-210d-report.json"
  rm -f "$report"
  if (cd ../FitValidation && swift run -c release fit-validation \
      --samples "../patch-pipeline/$(jq -r .samples <<<"$row")" \
      --events  "../patch-pipeline/$(jq -r .events  <<<"$row")" \
      --flood "$(jq -r .flood <<<"$row")" --ebb "$(jq -r .ebb <<<"$row")" \
      --label "$label") 2>&1 | tee "data/verdicts/${label}.log"; then
    echo PASS > "data/verdicts/${label}.status"
  else
    echo FAIL > "data/verdicts/${label}.status"
  fi
  [ -f "$report" ] && cp "$report" "data/verdicts/${label}.json"
  touch "data/verdicts/${label}.done"
done
```

- [ ] **Step 5: Run unit tests** — `uv run --with pytest,numpy,requests pytest -q test_certify.py` → PASS.

- [ ] **Step 6: Commit** — `git add tools/patch-pipeline && git commit -m "patch-pipeline: method-certification harness (certify_patch + run_certify)"`

---

### Task 4: RUN method certification — the phase's go/no-go

**Files:**
- Create: `tools/patch-pipeline/passes/CERTIFICATION.md`

**Interfaces:**
- Consumes: Tasks 2–3 outputs.
- Produces: the §6a verdict of record. **Every downstream BC task is gated on this being PASS at all four check stations.**

- [ ] **Step 1:** `cd tools/patch-pipeline && ./certify_patch.py` — generates 4 sample/event pairs (tacoma-narrows-PUG1524/-PUG1526/-PUG1528, deception-pass-PUG1629).
- [ ] **Step 2:** `./run_certify.sh` — one FitValidation run per pair (~minutes each).
- [ ] **Step 3:** Write `passes/CERTIFICATION.md`: per check station — status (from `.status`), the report's medians (read the exact keys from `tools/FitValidation/Sources/fit-validation/main.swift` around line 394: `speedMedianKn`, `speedMaxKn`, and the slack/extrema timing medians written beside them), distance from anchor, applied scale. Summary table first, SURVIVORS.md style.
- [ ] **Step 4 — CHECKPOINT:** If all four PASS → commit and continue. **If any FAIL: stop the phase here.** Commit the CERTIFICATION.md as-is, report to the owner with the failing numbers, and do not start Tasks 5–9 (spec §6a: the fallback is the composite §7 Discovery-FVCOM conversation, not a loosened bar). A partial outcome (e.g. Tacoma passes, Deception's Yokeko fails on slack timing) goes to the owner too — the spec's §9 shrink-applies-to-timing note (terminate the Deception patch west of Yokeko and re-run) is an owner decision, not an executor improvisation.
- [ ] **Step 5: Commit** — `git add tools/patch-pipeline/passes/CERTIFICATION.md && git commit -m "patch-pipeline: method certification verdicts (Tacoma + Deception)"`

---

### Task 5: `sensitivity.py` — perturbation sweep and truncation

**Files:**
- Create: `tools/patch-pipeline/sensitivity.py`, `tools/patch-pipeline/test_sensitivity.py`

**Interfaces:**
- Consumes: `build_pass` + `tile_depth_fn` from `sections.py`; `inputs/<slug>.json`; the committed `passes/<slug>.json`.
- Produces: narrowed `kept_range` written back into `passes/<slug>.json` + a `sensitivity` block (per-variant scale deltas) in the same file. Rule (spec §6b.2): a section is kept only if, across all variants, `|Δ(scale × spring_max_kn)| <= max(0.10 × scale × spring_max_kn, 0.25)`; `kept_range` is the longest contiguous run of kept sections containing the anchor. Shrink, never smooth.

- [ ] **Step 1: Write the failing test.**

```python
# tools/patch-pipeline/test_sensitivity.py — uv run --with pytest,numpy pytest -q test_sensitivity.py
from sensitivity import kept_range_from_deltas

def test_stable_everywhere_keeps_all():
    base = [1.0, 1.1, 1.3, 1.6]           # scales
    variants = [[1.0, 1.12, 1.31, 1.62]]  # small deltas
    assert kept_range_from_deltas(base, variants, anchor=0, spring_max_kn=4.0) == [0, 3]

def test_unstable_tail_truncated():
    base = [1.0, 1.1, 1.3, 3.0]
    variants = [[1.0, 1.1, 1.3, 5.0]]     # last section swings 8 kn at springs
    assert kept_range_from_deltas(base, variants, anchor=0, spring_max_kn=4.0) == [0, 2]

def test_range_must_contain_anchor():
    base = [3.0, 1.0, 1.1]
    variants = [[5.0, 1.0, 1.1]]          # unstable section 0 = the anchor itself
    try:
        kept_range_from_deltas(base, variants, anchor=0, spring_max_kn=4.0)
        assert False, "anchor section unstable must be a hard error"
    except SystemExit:
        pass
```

- [ ] **Step 2: Run to verify failure** → FAIL (`sensitivity` not found).

- [ ] **Step 3: Implement.**

```python
#!/usr/bin/env -S uv run --script --with numpy,rasterio
"""Slackwater patch-pipeline — cross-section sensitivity sweep (spec §6b.2).

Variants: sections shifted +/- half a spacing along the thalweg; datum at
chart datum (cd_to_mwl_m = 0) instead of MWL. Any section whose spring-peak
speed (scale x anchor spring_max_kn) moves more than max(10%, 0.25 kn) under
any variant is dropped; kept_range = longest contiguous stable run containing
the anchor. The committed pass artifact is updated in place — shrink, never
smooth.
"""
import json, sys
from sections import build_pass, tile_depth_fn


def kept_range_from_deltas(base_scales, variant_scales, anchor, spring_max_kn):
    keep = []
    for i, s in enumerate(base_scales):
        bar = max(0.10 * s * spring_max_kn, 0.25)
        ok = all(i < len(v) and abs(v[i] - s) * spring_max_kn <= bar for v in variant_scales)
        keep.append(ok)
    if not keep[anchor]:
        raise SystemExit("anchor section is sensitivity-unstable — bad tiles or bad anchor placement")
    lo = anchor
    while lo > 0 and keep[lo - 1]:
        lo -= 1
    hi = anchor
    while hi < len(keep) - 1 and keep[hi + 1]:
        hi += 1
    return [lo, hi]


def variant(inputs, depth_at, shift_frac=0.0, cd_override=None):
    v = dict(inputs)
    if cd_override is not None:
        v = dict(v, cd_to_mwl_m=cd_override)
    if shift_frac:
        # shift the seed start point along itself by shift_frac of a spacing:
        # cheap re-jitter of every downstream station position
        seed = [list(p) for p in v["thalweg_seed"]]
        f = shift_frac
        seed[0] = [seed[0][0] + (seed[1][0] - seed[0][0]) * f,
                   seed[0][1] + (seed[1][1] - seed[0][1]) * f]
        v = dict(v, thalweg_seed=seed)
    return build_pass(v, depth_at)


def main(slug):
    inputs = json.load(open(f"inputs/{slug}.json"))
    doc = json.load(open(f"passes/{slug}.json"))
    depth_mwl = tile_depth_fn(f"data/tiles/{slug}", inputs["tile_value"], inputs["cd_to_mwl_m"])
    depth_cd = tile_depth_fn(f"data/tiles/{slug}", inputs["tile_value"], 0.0)
    variants = [
        variant(inputs, depth_mwl, shift_frac=+0.5),
        variant(inputs, depth_mwl, shift_frac=-0.5),
        variant(inputs, depth_cd, cd_override=0.0),
    ]
    # align by section index; variant runs may differ in count — compare the overlap
    vscales = [v["scales"] for v in variants]
    kr = kept_range_from_deltas(doc["scales"], vscales,
                                doc["anchor"]["section_index"],
                                doc["anchor"]["spring_max_kn"])
    doc["kept_range"] = kr
    doc["sensitivity"] = {"variants": ["shift+0.5", "shift-0.5", "datum=CD"],
                          "dropped_below": kr[0], "dropped_above": len(doc["scales"]) - 1 - kr[1]}
    json.dump(doc, open(f"passes/{slug}.json", "w"), indent=1)
    print(f"{slug}: kept sections {kr[0]}..{kr[1]} of 0..{len(doc['scales']) - 1}")


if __name__ == "__main__":
    main(sys.argv[1])
```

- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Run on the US pair:** `./sensitivity.py tacoma-narrows && ./sensitivity.py deception-pass`. Re-run `certify_patch.py` + `run_certify.sh` if `kept_range` narrowed past a check station (a check station falling outside `kept_range` now hard-errors — that means the patch no longer covers it and the certification table must say so; escalate to owner if it was a passing station).
- [ ] **Step 6: Commit** — `git add tools/patch-pipeline && git commit -m "patch-pipeline: sensitivity sweep truncation (shrink, never smooth)"`

---

### Task 6: `pack.py` — the patches bundle

**Files:**
- Create: `tools/patch-pipeline/pack.py`, `tools/patch-pipeline/test_pack.py`
- Create (generated): `Slackwater/Resources/patches-salish.bin`, `Slackwater/Resources/patches-salish.json`
- Modify: `Slackwater.xcodeproj/project.pbxproj` (register the two resources exactly the way `fill-salish.bin`/`fill-salish.json` are registered — grep the pbxproj for `fill-salish` and mirror all entries with new UUIDs)

**Interfaces:**
- Consumes: `passes/<slug>.json` (kept_range narrowed).
- Produces the format Task 7 decodes. **Binary layout, little-endian, cells concatenated per patch, fixed 30-byte cells:**

```
per cell:
    3 x (f32 lon, f32 lat)      # triangle vertices (24 B)
    f16 scale                   # A(anchor)/A(here)
    f16 bearing_deg             # flood set direction
    f16 width_m                 # local channel width (channel-2 sample extent)
```

Cells: for each kept section interval [i, i+1], quad (left_i, right_i, right_{i+1}, left_{i+1}) split into triangles (left_i, right_i, right_{i+1}) and (left_i, right_{i+1}, left_{i+1}); cell scale = mean(scales[i], scales[i+1]); bearing = bearing between section centers; width = mean widths. Sidecar:

```json
{"format_version": 1, "region": "salish", "generated": "...", "bin_sha256": "...",
 "patches": [{"id": "tacoma-narrows", "anchor": {"provider": "noaa", "station_id": "PUG1527"},
              "cell_count": 48, "offset": 0, "source_sha256": "<sha256 of passes/<slug>.json>"}]}
```

`offset` = byte offset of the patch's first cell; cells are fixed-size so no per-cell offsets. Size gate: hard `SystemExit` if bin > 1 MB (spec §7.3's 100 KB expectation with 10× headroom — this bundle has no business being big).

- [ ] **Step 1: Write the failing test** — mirror `tools/fill-pipeline/test_pack.py`'s independent-reader pattern:

```python
# tools/patch-pipeline/test_pack.py — uv run --with pytest pytest -q test_pack.py
import json, struct
from pack import pack_patches

PASS_DOC = {
    "slug": "synthetic", "anchor": {"provider": "noaa", "station_id": "TEST1", "section_index": 0},
    "sections": [
        {"center": [0.0, 0.0], "bearing_deg": 10.0, "width_m": 100.0,
         "left": [-0.001, 0.0], "right": [0.001, 0.0]},
        {"center": [0.0, 0.001], "bearing_deg": 10.0, "width_m": 120.0,
         "left": [-0.001, 0.001], "right": [0.001, 0.001]},
    ],
    "scales": [1.0, 0.5], "kept_range": [0, 1],
}

def _read_cells(bin_bytes, count):
    out, pos = [], 0
    for _ in range(count):
        verts = []
        for _ in range(3):
            lon, lat = struct.unpack_from("<ff", bin_bytes, pos)
            verts.append((lon, lat))
            pos += 8
        scale, bearing, width = struct.unpack_from("<eee", bin_bytes, pos)
        pos += 6
        out.append({"verts": verts, "scale": scale, "bearing": bearing, "width": width})
    return out

def test_roundtrip_two_triangles_per_interval(tmp_path):
    bin_bytes, header = pack_patches([PASS_DOC])
    assert header["patches"][0]["cell_count"] == 2
    cells = _read_cells(bin_bytes, 2)
    for c in cells:
        assert abs(c["scale"] - 0.75) < 0.01      # mean(1.0, 0.5)
        assert abs(c["width"] - 110.0) < 0.5
    assert len(bin_bytes) == 2 * 30

def test_only_kept_range_ships():
    doc = dict(PASS_DOC, kept_range=[0, 0])       # single section -> no interval -> no cells
    bin_bytes, header = pack_patches([doc])
    assert header["patches"][0]["cell_count"] == 0

def test_size_gate_fires():
    import pack
    big = [dict(PASS_DOC, slug=f"p{i}") for i in range(5)]
    try:
        pack.pack_patches(big, max_bytes=100)
        assert False, "size gate must SystemExit"
    except SystemExit:
        pass
```

- [ ] **Step 2: Run to verify failure** → FAIL.
- [ ] **Step 3: Implement `pack.py`** (module docstring = the normative layout, like fill's; `pack_patches(pass_docs, max_bytes=1_048_576) -> (bytes, header_dict)` pure core + `main()` that reads every `passes/*.json`, computes `bearing between centers` with the same `_bearing_deg` as `sections.py` (import it), writes `Slackwater/Resources/patches-salish.{bin,json}` with `generated`, `bin_sha256`, per-patch `source_sha256`; struct format `"<ffffffeee"` per cell via `struct.pack("<ff", ...)` per vertex + `struct.pack("<eee", scale, bearing, width)`).
- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Run `./pack.py`** — packs the certified US pair; confirm the printed size is single-digit KB. Register both resources in the Xcode project (mirror the `fill-salish` pbxproj entries). `xcodebuild -scheme Slackwater build` (or the repo's standard build lane) to confirm the project still builds with the resources present.
- [ ] **Step 6: Commit** — `git add tools/patch-pipeline Slackwater/Resources/patches-salish.* Slackwater.xcodeproj && git commit -m "patch-pipeline: pack patches-salish bundle (US certification pair)"`

---

### Task 7: `PatchField` — the runtime provider

**Files:**
- Create: `Slackwater/PatchField.swift`, `SlackwaterTests/PatchFieldTests.swift`
- Modify: `Slackwater/FillField.swift` (one word: `private struct FillByteReader` → `struct FillByteReader` — reuse, don't duplicate, the byte reader)
- Modify: `Slackwater.xcodeproj/project.pbxproj` if new files need registration (mirror `FillField.swift`'s entries)

**Interfaces:**
- Consumes: `patches-salish.{bin,json}` (Task 6 layout); `FillCell`, `FillBBox`, `FillByteReader` (FillField.swift); `CurrentStationRecord.all` / `.engineStation` / `setDegrees` semantics (CurrentStation.swift); `ChsCurrentGateInfo.all`, `ChsModelStore.loadCurrent(_:)`, `gate.record(with:)` (ChsCurrentGate.swift).
- Produces (the seam):

```swift
struct PatchSample {                 // channel-2 oriented flow sample (spec §5)
    let center: CLLocationCoordinate2D
    let bearingDeg: Double
    let signedKn: Double
    let extentM: Double
}
final class PatchField {
    convenience init?(resource: String = "patches-salish")
    init?(bin: Data, headerJSON: Data)
    func cells(at date: Date, in bbox: FillBBox? = nil) -> [FillCell]
    func samples(at date: Date) -> [PatchSample]
}
```

Behavioral contract: per patch per call, evaluate the anchor **once** (CHS: `ChsCurrentGateInfo.all` lookup → `ChsModelStore.loadCurrent(id)` → `gate.record(with: model)`; NOAA: `CurrentStationRecord.all` lookup; then `record.engineStation.speeds(from: t, to: t+1, step: 1).first?.speed` — the app-wide 1-second-window idiom). `speedKn = |signed| × scale`; `bearingDeg = signed >= 0 ? cellBearing : (cellBearing + 180).truncatingRemainder(dividingBy: 360)` (the `setDegrees(signed:)` semantics applied to a per-cell axis). **An anchor that can't resolve (unknown id, CHS model not yet fitted on device) vends no cells for that patch — absence stays absence, no partial/flagged state.** Note: `ChsModelStore.loadCurrent` — check its actor isolation before calling from a non-main context; if it is `@MainActor`, mark `PatchField.cells(at:)`'s anchor resolution accordingly (the fill consumer evaluates off-main once a minute; patches are tiny, main-actor resolution at that cadence is acceptable — mirror whatever `ChsFitService`-adjacent code does).

- [ ] **Step 1: Write failing tests.**

```swift
// SlackwaterTests/PatchFieldTests.swift
import XCTest
@testable import Slackwater

final class PatchFieldTests: XCTestCase {
    /// Fixture: one patch, anchor = bundled NOAA station PUG1701, two cells
    /// (scale 0.5 / bearing 90 / width 200; scale 2.0 / bearing 270 / width 300).
    private func fixture(anchorId: String = "PUG1701") -> (Data, Data) {
        var bin = Data()
        func cell(_ verts: [(Double, Double)], _ scale: Float16, _ bearing: Float16, _ width: Float16) {
            for (lon, lat) in verts {
                withUnsafeBytes(of: Float(lon).bitPattern.littleEndian) { bin.append(contentsOf: $0) }
                withUnsafeBytes(of: Float(lat).bitPattern.littleEndian) { bin.append(contentsOf: $0) }
            }
            for v: Float16 in [scale, bearing, width] {
                withUnsafeBytes(of: v.bitPattern.littleEndian) { bin.append(contentsOf: $0) }
            }
        }
        cell([(-122.64, 48.40), (-122.63, 48.40), (-122.63, 48.41)], 0.5, 90, 200)
        cell([(-122.64, 48.41), (-122.63, 48.41), (-122.63, 48.42)], 2.0, 270, 300)
        let header = """
        {"format_version": 1, "region": "salish", "patches":
         [{"id": "test-pass", "anchor": {"provider": "noaa", "station_id": "\(anchorId)"},
           "cell_count": 2, "offset": 0}]}
        """
        return (bin, Data(header.utf8))
    }

    func testCellsScaleAnchorSpeed() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "PUG1701" })
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let signed = try XCTUnwrap(anchor.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed)
        let cells = field.cells(at: date)
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells[0].speedKn, abs(signed) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(cells[1].speedKn, abs(signed) * 2.0, accuracy: 1e-9)
        let expected0 = signed >= 0 ? 90.0 : 270.0
        XCTAssertEqual(cells[0].bearingDeg, expected0, accuracy: 0.1)
    }

    func testUnresolvableAnchorVendsNothing() throws {
        let (bin, header) = fixture(anchorId: "NO-SUCH-STATION")
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        XCTAssertTrue(field.cells(at: Date()).isEmpty)   // absence stays absence
    }

    func testBBoxCullUsesTriangleExtent() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let tiny = FillBBox(minLon: -122.636, minLat: 48.402, maxLon: -122.635, maxLat: 48.403)
        XCTAssertEqual(field.cells(at: Date(), in: tiny).count, 1)  // inside cell 0 only
    }

    func testSamplesCarrySignAndExtent() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "PUG1701" })
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let signed = try XCTUnwrap(anchor.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed)
        let samples = field.samples(at: date)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].signedKn, signed * 0.5, accuracy: 1e-9)
        XCTAssertEqual(samples[0].extentM, 200, accuracy: 0.5)
    }

    func testMalformedHeaderFailsInit() {
        let (bin, _) = fixture()
        XCTAssertNil(PatchField(bin: bin, headerJSON: Data("{}".utf8)))
        XCTAssertNil(PatchField(bin: Data(), headerJSON: {
            let (_, h) = fixture(); return h
        }()))  // cell_count*30 != bin length
    }

    func testRealBundleLoads() throws {
        // Activates once patches-salish.bin is committed; mirrors FillFieldTests' skip idiom.
        guard let field = PatchField() else { throw XCTSkip("patches-salish not bundled yet") }
        XCTAssertFalse(field.cells(at: Date(timeIntervalSince1970: 1_787_000_000)).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure** — run the repo's standard test lane (see `.claude/skills` / previous task briefs for the exact `xcodebuild test` invocation used by FillFieldTests) → compile FAIL (`PatchField` undefined).
- [ ] **Step 3: Implement `Slackwater/PatchField.swift`.** Structure mirrors FillField top to bottom: GPL header comment stating the 30-byte cell layout (this file + pack.py's docstring are the two statements that must agree), `PatchHeader: Decodable` (`format_version`, `patches[]` with `id/anchor/cell_count/offset`), init validation (`formatVersion == 1`, `Σ cell_count × 30 == bin.count`, offsets consistent), `FillByteReader` reused for decoding, anchor resolution + evaluation as specified in the Interfaces block above, `cells(at:in:)` applying the bbox `overlaps` cull per cell, `samples(at:)` vending centroids. Change `private struct FillByteReader` to `struct FillByteReader` in FillField.swift.
- [ ] **Step 4: Run tests** → PASS (including `testRealBundleLoads` now the bundle exists from Task 6).
- [ ] **Step 5: Commit** — `git add Slackwater/PatchField.swift Slackwater/FillField.swift SlackwaterTests/PatchFieldTests.swift Slackwater.xcodeproj && git commit -m "feat: PatchField — grown-patch provider vending FillCells + channel-2 samples"`

---

### Task 8: BC passes — Dodd, Seymour, Porlier  **[GATED on Task 4 = PASS]**

**Files:**
- Create: `tools/patch-pipeline/inputs/{dodd-narrows,seymour-narrows,porlier-pass}.json`, `tools/patch-pipeline/passes/{dodd-narrows,seymour-narrows,porlier-pass}.json`
- Modify: `tools/patch-pipeline/passes/CERTIFICATION.md` (per-patch §6b verdicts)

**Interfaces:**
- Consumes: everything Tasks 1–5 built; NONNA-10 tiles (manual download per the README runbook — CHS portal account, licence acceptance recorded in each MANIFEST).
- Produces: three committed BC pass artifacts, sensitivity-truncated, springs-checked.

- [ ] **Step 1: Author the three inputs.** Anchors from `station-corrections/data/registry.json` + `Slackwater/Resources/chs-current-gates.json` (`chs-dodd-narrows` 49.1344/−123.8171, `chs-seymour-narrows` 50.1333/−125.35, `chs-porlier-pass` 49.015/−123.585; provider `"chs"`). `flood_deg`: from each gate's fitted axis — `jq` the on-device model is not available offline, so use the flood direction the certification data already captured: `tools/fill-pipeline/data/stations.json` carries `flood`/`ebb` per slug (dodd-narrows, seymour-narrows, porlier-pass). `spring_max_kn` from published CHS tables (Dodd ~9, Seymour ~15–16, Porlier ~9 — verify against the current atlas / gate detail copy in the app; record the source in the inputs `notes`). `cd_to_mwl_m` from the pass's reference tide station MWL (IWLS station metadata; Seymour → chs-campbell-river, Porlier → chs-fulford-harbour, Dodd → nearest of the Nanaimo ports). `tile_value: "depth"`. `check_stations: []` (none exist — that is why Task 4 gates this). Ends per spec: Dodd (~1 width past each mouth, no junctions); Seymour (Race/Maud Island narrows core, ending before Menzies Bay embayment S and Brown Bay N); Porlier (between the Strait mouth and the inside junction fan) — write the reasons into `ends`.
- [ ] **Step 2: Download NONNA-10 GeoTIFF tiles** for the three passes into `data/tiles/<slug>/` + MANIFESTs (licence-acceptance date + verbatim-notice obligation noted per tile).
- [ ] **Step 3: Run `sections.py` + `sensitivity.py` per pass.** Expect Dodd's kept_range to shrink hardest (spec §9 — 60–80 m throat vs 10 m tiles). Hard check: each pass's anchor-section scale = 1.0; Dodd throat `width_m` must read ~60–120 m — if it reads hundreds, the wet-run grabbed False Narrows or the tile datum sign is wrong.
- [ ] **Step 4: Springs plausibility (§6b.3):** for each pass, `max(scale over kept_range) × spring_max_kn` must land within ~15 % of the gate's published spring maximum at the throat (the throat is where scale peaks — for Dodd that product should read ≈ 9–10 kn, the composite §8.2 number). Record the three numbers in CERTIFICATION.md.
- [ ] **Step 5: Render review plots** (as Task 2 Step 5) for the PR.
- [ ] **Step 6: Commit** — `git add tools/patch-pipeline && git commit -m "patch-pipeline: BC passes (Dodd, Seymour, Porlier) — sections, sensitivity, springs checks"`

---

### Task 9: Repack with BC + the CHS NONNA notice

**Files:**
- Modify: `Slackwater/Resources/patches-salish.{bin,json}` (regenerate), `Slackwater/SettingsView.swift`

**Interfaces:**
- Consumes: Task 8's pass artifacts; Task 6's pack.py; the existing "Data & attribution" section in SettingsView (~line 67).
- Produces: the shipping 5-patch bundle + the licence notice, in one change (spec §7.5: same release).

- [ ] **Step 1:** `./pack.py` — repack all five passes. Size still single-digit KB.
- [ ] **Step 2:** Add the NONNA notice to SettingsView's "Data & attribution" section, alongside the existing CHS clause-10 text. New `Text` entry: the **verbatim** notice required by the NONNA licence — copy it exactly from the licence PDF recorded in the Task 8 MANIFESTs (clause 7's required attribution statement), plus one sentence in app voice: "Channel cross-sections for grown current patches are derived from CHS NONNA-10 bathymetry under this licence; raw survey data is not included." Do not paraphrase the verbatim part.
- [ ] **Step 3:** Run the full test suite (PatchFieldTests' real-bundle test now exercises the 5-patch bundle; `testRealBundleLoads` gains BC patches whose CHS anchors won't resolve on the test host — confirm the test still passes because the NOAA-anchored patches vend cells; if the host happens to have no fitted CHS models, BC patches vending nothing is correct absence, not failure).
- [ ] **Step 4: Commit** — `git add Slackwater/Resources/patches-salish.* Slackwater/SettingsView.swift && git commit -m "feat: ship BC grown patches (Dodd, Seymour, Porlier) + CHS NONNA verbatim notice"`

---

### Task 10: Final assembly — runbook, certification record, PR

**Files:**
- Modify: `tools/patch-pipeline/README.md`, `tools/patch-pipeline/passes/CERTIFICATION.md`

- [ ] **Step 1: Drift check** (spec §6b.5): re-run `sections.py` for one pass; `git diff tools/patch-pipeline/passes/` must show only the `generated` timestamp. Record the check in README as the standing release-time procedure (mirror the fill-refit runbook note in `docs/`).
- [ ] **Step 2: CERTIFICATION.md final form:** method-certification table (Task 4), per-patch §6b results (Tasks 5/8), springs numbers, kept_range per pass. This file is the phase's verdict of record, SURVIVORS.md style.
- [ ] **Step 3: Verify spec success criteria (§7) one by one** — write the five checks + observed values into the PR body: 4/4 check stations PASS; Dodd ≈ 9.5 kn springs (actual number); bundle size (actual bytes); traceability (every patch has a passes/*.json + anchor); NONNA notice present.
- [ ] **Step 4:** `git log --oneline origin/main..HEAD` — only this phase's commits. Open the PR with the review plots attached (bounds review is the owner's §6b.4 gate) — do not merge it.

---

## Self-Review Notes

- **Spec coverage:** §0/§1 scope → Tasks 2/8 (pass selection is fixed by the plan's file list); §2 pipeline → Tasks 1/2/8; §3 construction → Tasks 1 (speed/direction/bounds via inputs+sections) — direction is thalweg-tangent per decision 3, no Laplace task on purpose; §4 format → Task 6; §5 runtime → Task 7; §6a → Tasks 3/4; §6b → Tasks 5/8/10 (bounds review = PR plots, drift = Task 10); §7 criteria → Task 10 Step 3; NONNA notice → Task 9. Tier 2 (Gillard, Race) is deliberately NOT in this plan — same pipeline, next release, per spec §1.
- **Known executor judgment points, flagged not hidden:** thalweg seeds and `ends` reasons are hand-authored against real charts (Tasks 2/8 give per-pass guidance + hard numeric guards); `make_matrix.py` import guard must be verified (Task 3 Step 3 note); `ChsModelStore.loadCurrent` actor isolation (Task 7 Interfaces note); FitValidation report keys read from main.swift at Task 4 Step 3.
- **Type consistency:** `FillCell`/`FillBBox` reused unchanged; `pack_patches` layout ↔ test reader ↔ PatchField header comment are the three statements that must agree (Tasks 6/7 both say so); `passes/<slug>.json` schema defined once (header) and referenced by Tasks 3/5/6.
