# SSCOFS Field Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decide, with measured numbers on the app's exact shipping fit/predict path, whether SSCOFS-derived per-element harmonics can be a certified current-field backdrop (spec §3, `docs/superpowers/specs/2026-08-20-current-field-composite-design.md`).

**Architecture:** Python scripts (in `spikes/sscofs-field/`) fetch a 60-day surface u/v corpus for one box via HTTP ranged reads, project element velocities onto each truth station's flood axis, and export samples + held-out truth events as JSON. The existing `tools/FitValidation` Swift harness grows a file-input mode so the fit (`fitTides` in JavaScriptCore) and prediction (`TideEngine.CurrentStation`) are byte-for-byte the shipping path. A report script aggregates the five-bar verdicts and extrapolates bundle size.

**Tech Stack:** Python via `uv run --with h5py,fsspec,aiohttp,numpy,requests,pytest` (no project venv — spike convention), Swift (existing FitValidation package), the committed `chs-bundle.js`/`chs-glue.js` JS artifacts.

## Global Constraints

- **The bar** (verbatim from `spikes/chs-currents-fit/README.md`, PASS = all five): slack timing median ≤ 15 min; slack worst ≤ 30 min (every observed slack must match within 180 min); extremum timing median ≤ 20 min (extrema ≥ 0.75 kn); peak speed median error ≤ 0.5 kn; no systematic axis flip (wrong-sign ≥ 60 % of extrema quarantines).
- **Spike box:** lon −123.95..−122.55, lat 48.30..49.25 (southern Gulf Islands + San Juans; contains Active Pass ratio 1.00 and Dodd Narrows ratio 0.24 — both outcomes represented).
- **Corpus:** 60 days of hourly surface u/v ending at run date, nowcast files only, from `https://noaa-nos-ofs-pds.s3.amazonaws.com/sscofs/netcdf/YYYY/MM/DD/sscofs.tHHz.YYYYMMDD.fields.nNNN.nc`; per day use cycles {03,09,15,21} × files n001..n006 = 24 hourly steps. ~14 MB transferred per file (ranged reads), ~1,440 files, ~20 GB, ≥4 but ≤6 concurrent requests.
- **Held-out validation window:** published events +28..+35 days after the fit epoch (the chs-currents-fit convention).
- **Decision gates (spec §3):** certifiable sub-regions meet the bar; Dodd-class stations correctly FAIL; extrapolated bundle ≤ 40 MB. Any gate failing → spike concludes Plan B (grown patches only), and that is a *successful* spike outcome — record it, don't rescue it.
- **fitTides input shape:** JSON array `[{"t":<epoch seconds>,"v":<signed knots>}]` (main.swift:232). **Events shape:** `[{"eventDate": ISO8601, "qualifier": "SLACK"|"EXTREMA_FLOOD"|"EXTREMA_EBB", "value": <kn, positive>}]` (main.swift:151, 200-209).
- Everything under `spikes/sscofs-field/`; no app-target code changes; FitValidation is the only tool modified.
- SSCOFS units: u/v in m/s → knots ×1.94384. Direction convention: bearing the flow sets TOWARD, `dir = atan2(u, v)` in degrees true, normalized 0..360 — matching IWLS `wcdp1` so the harness projection `v·cos(dir−flood)` transfers unchanged.

## File Structure

```
spikes/sscofs-field/
  README.md              # method + verdict (Task 7)
  mesh_subset.py         # Task 1 → mesh/elements.json
  fetch_corpus.py        # Task 2 → corpus/YYYYMMDD.npz shards
  truth_stations.py      # Task 3 → truth/stations.json (id, pos, axis, source)
  make_samples.py        # Task 4 → samples/<station>-<elem>.json + truth/<station>-events.json
  test_project.py        # Task 4 unit test (projection math)
  run_matrix.sh          # Task 6 → runs fit-validation over all pairs
  report.py              # Task 6 → RESULTS.md + size extrapolation
tools/FitValidation/Sources/fit-validation/main.swift   # Task 5: file-input mode
```

---

### Task 1: Mesh box subset

**Files:**
- Create: `spikes/sscofs-field/mesh_subset.py`

**Interfaces:**
- Produces: `spikes/sscofs-field/mesh/elements.json` — `{"file": "<source nc>", "box": [-123.95, 48.30, -122.55, 49.25], "elements": [{"i": <0-based element index in full mesh>, "lon": <lonc>, "lat": <latc>}...]}`. Every later task reads element indices from here.

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env -S uv run --script --with h5py,fsspec,aiohttp,numpy,requests
"""Subset SSCOFS element centroids to the spike box. Downloads one fields file header remotely (ranged reads) — no full download."""
import json, sys, datetime as dt
import numpy as np, h5py, fsspec

BOX = (-123.95, 48.30, -122.55, 49.25)  # lonW, latS, lonE, latN
BUCKET = "https://noaa-nos-ofs-pds.s3.amazonaws.com/sscofs/netcdf"

def latest_url(days_back=1):
    d = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days_back)
    return f"{BUCKET}/{d:%Y/%m/%d}/sscofs.t03z.{d:%Y%m%d}.fields.n001.nc"

def main():
    url = sys.argv[1] if len(sys.argv) > 1 else latest_url()
    with h5py.File(fsspec.open(url, "rb").open(), "r") as f:
        lonc, latc = f["lonc"][:], f["latc"][:]
    lonc = np.where(lonc > 180, lonc - 360, lonc)
    w, s, e, n = BOX
    idx = np.where((lonc >= w) & (lonc <= e) & (latc >= s) & (latc <= n))[0]
    out = {"file": url, "box": list(BOX),
           "elements": [{"i": int(i), "lon": float(lonc[i]), "lat": float(latc[i])} for i in idx]}
    with open("mesh/elements.json", "w") as fh:
        json.dump(out, fh)
    print(f"{len(idx)} elements in box (full mesh {len(lonc)})")
    # Self-check: the five reference passes must each have an element within 600 m.
    refs = {"dodd": (49.1367, -123.8183), "active": (48.8667, -123.3000),
            "boundary": (48.7621, -123.0520), "sanjuan": (48.4600, -122.9500)}
    for name, (la, lo) in refs.items():
        dmin = float(np.min(np.hypot((latc[idx] - la) * 111320,
                                     (lonc[idx] - lo) * 111320 * np.cos(np.radians(la)))))
        assert dmin < 600, f"{name}: nearest element {dmin:.0f} m"
        print(f"  {name}: nearest element {dmin:.0f} m")

if __name__ == "__main__":
    import os; os.makedirs("mesh", exist_ok=True); main()
```

- [ ] **Step 2: Run it and verify the self-check passes**

Run: `cd spikes/sscofs-field && ./mesh_subset.py`
Expected: element count (order 10⁴), four "nearest element < 600 m" lines, no assert. If `lonc`/`latc` names differ in the file, `h5py` will KeyError — list keys with `h5py.File(...).keys()` and fix (the measured file used `lonc`/`latc`).

- [ ] **Step 3: Commit**

```bash
git add spikes/sscofs-field/mesh_subset.py
git commit -m "spike(sscofs-field): mesh box subset with pass-proximity self-check"
```

### Task 2: Corpus fetcher (resumable)

**Files:**
- Create: `spikes/sscofs-field/fetch_corpus.py`

**Interfaces:**
- Consumes: `mesh/elements.json` (Task 1).
- Produces: `corpus/YYYYMMDD.npz` per day, arrays: `t` shape (24,) float64 epoch seconds; `u`, `v` shape (24, N) float32 m/s, N = box element count, column order = `elements.json` order. Missing hours are NaN columns-of-row; a day file is written only when ≥ 20 of 24 hours succeeded.

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env -S uv run --script --with h5py,fsspec,aiohttp,numpy
"""Fetch 60 days of hourly surface u/v for the box elements. Resumable: skips existing day files."""
import json, os, sys, datetime as dt, concurrent.futures as cf
import numpy as np, h5py, fsspec

BUCKET = "https://noaa-nos-ofs-pds.s3.amazonaws.com/sscofs/netcdf"
CYCLES = (3, 9, 15, 21)          # ×n001..n006 → 24 hourly steps/day
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 60

def hour_urls(day):
    for c in CYCLES:
        for n in range(1, 7):
            yield (f"{BUCKET}/{day:%Y/%m/%d}/sscofs.t{c:02d}z.{day:%Y%m%d}.fields.n{n:03d}.nc",
                   dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc)
                   + dt.timedelta(hours=c - 6 + n))   # verify offset in Step 2 and fix if needed

def fetch_hour(url, idx):
    try:
        with h5py.File(fsspec.open(url, "rb").open(), "r") as f:
            return f["u"][0, 0, :][idx], f["v"][0, 0, :][idx]   # surface = siglay 0
    except Exception as e:
        print(f"  miss {url.rsplit('/',1)[1]}: {type(e).__name__}")
        return None

def main():
    els = json.load(open("mesh/elements.json"))["elements"]
    idx = np.array([e["i"] for e in els])
    os.makedirs("corpus", exist_ok=True)
    today = dt.datetime.now(dt.timezone.utc).date()
    for back in range(DAYS, 0, -1):
        day = today - dt.timedelta(days=back)
        out = f"corpus/{day:%Y%m%d}.npz"
        if os.path.exists(out):
            continue
        pairs = list(hour_urls(dt.datetime(day.year, day.month, day.day)))
        t = np.array([ts.timestamp() for _, ts in pairs])
        u = np.full((24, len(idx)), np.nan, np.float32); v = u.copy()
        with cf.ThreadPoolExecutor(max_workers=5) as ex:
            futs = {ex.submit(fetch_hour, url, idx): k for k, (url, _) in enumerate(pairs)}
            for fut in cf.as_completed(futs):
                r = fut.result()
                if r is not None:
                    u[futs[fut]], v[futs[fut]] = r
        ok = int(np.isfinite(u[:, 0]).sum())
        if ok >= 20:
            np.savez_compressed(out, t=t, u=u, v=v)
        print(f"{day} {ok}/24 hours {'saved' if ok >= 20 else 'SKIPPED'}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify the time mapping on 2 days before the long run**

Run: `cd spikes/sscofs-field && ./fetch_corpus.py 2`
Then check the nowcast file's own time variable against the assumed stamp: open one URL in a python one-liner, read `f["time"]` (or `Times`) plus its units attribute, and compare with the `hour_urls` offset (`c - 6 + n`). **If they disagree, fix `hour_urls` to match the file's declared valid time and re-run.** Expected: two `.npz` files, mostly 24/24, speeds `np.hypot(u,v)` finite and < 8 m/s.

- [ ] **Step 3: Commit, then launch the full fetch in the background**

```bash
git add spikes/sscofs-field/fetch_corpus.py
git commit -m "spike(sscofs-field): resumable 60-day surface u/v corpus fetcher"
./fetch_corpus.py 60   # ~1.5-2 h; resumable, safe to re-run
```

### Task 3: Truth-station table

**Files:**
- Create: `spikes/sscofs-field/truth_stations.py`

**Interfaces:**
- Produces: `truth/stations.json` — `[{"slug": "active-pass", "source": "chs"|"noaa", "id": "07527"|"PUG1515", "lat": .., "lon": .., "flood": <deg true>, "ebb": <deg true>}...]` for every current truth station inside the box. CHS entries: the box's registry gates (expected: Active Pass 07527, Dodd Narrows 07487, Porlier Pass, Gabriola Passage — confirm against the app registry, `tools/gen-chs-gates.mjs` output). NOAA entries: type-H current stations in the box from the MDAPI.

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env -S uv run --script --with requests
"""Build the truth-station table for the box: CHS gates (IWLS metadata axis) + NOAA type-H current stations (currents_predictions metadata axis)."""
import json, os, requests

BOX = (-123.95, 48.30, -122.55, 49.25)
IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
MD = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi"
CP = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

def inbox(lat, lon):
    w, s, e, n = BOX
    return s <= lat <= n and w <= lon <= e

def chs_gates():
    out = []
    for st in requests.get(f"{IWLS}/stations", timeout=60).json():
        if not inbox(st["latitude"], st["longitude"]):
            continue
        codes = {s["code"] for s in st.get("timeSeries", [])}
        if "wcp1-events" not in codes:
            continue
        meta = requests.get(f"{IWLS}/stations/{st['id']}/metadata", timeout=60).json()
        if meta.get("floodDirection") is None:
            continue
        out.append({"slug": st["officialName"].lower().replace(" ", "-"),
                    "source": "chs", "id": st["code"], "iwlsId": st["id"],
                    "lat": st["latitude"], "lon": st["longitude"],
                    "flood": meta["floodDirection"], "ebb": meta["ebbDirection"]})
    return out

def noaa_stations():
    out = []
    js = requests.get(f"{MD}/stations.json?type=currentpredictions&units=english", timeout=120).json()
    for st in js["stations"]:
        if not inbox(st["lat"], st["lng"]) or st.get("type") != "H":
            continue
        # meanFloodDir/meanEbbDir come back with any currents_predictions data request
        r = requests.get(CP, params={"station": st["id"], "product": "currents_predictions",
                                     "date": "today", "range": "24", "interval": "MAX_SLACK",
                                     "units": "english", "time_zone": "gmt", "format": "json"},
                         timeout=60).json()
        cp = r.get("current_predictions", {})
        if not cp.get("cp"):
            continue
        out.append({"slug": st["name"].lower().replace(" ", "-")[:40].strip("-"),
                    "source": "noaa", "id": st["id"], "lat": st["lat"], "lon": st["lng"],
                    "flood": float(cp["meanFloodDir"]), "ebb": float(cp["meanEbbDir"])})
    return out

if __name__ == "__main__":
    os.makedirs("truth", exist_ok=True)
    stations = chs_gates() + noaa_stations()
    json.dump(stations, open("truth/stations.json", "w"), indent=1)
    print(f"{len(stations)} truth stations "
          f"({sum(s['source']=='chs' for s in stations)} CHS, "
          f"{sum(s['source']=='noaa' for s in stations)} NOAA)")
    assert any("dodd" in s["slug"] for s in stations), "Dodd Narrows missing — box or filter wrong"
    assert any("active" in s["slug"] for s in stations), "Active Pass missing"
```

- [ ] **Step 2: Run and verify**

Run: `cd spikes/sscofs-field && ./truth_stations.py`
Expected: both asserts pass; total order 10–40 stations. If the IWLS station list or MDAPI response shapes differ from the fields used here, print one raw entry and adapt — the harness (`main.swift:151-174`) documents the IWLS metadata shape.

- [ ] **Step 3: Commit**

```bash
git add spikes/sscofs-field/truth_stations.py
git commit -m "spike(sscofs-field): truth-station table (CHS gates + NOAA type-H) with axes"
```

### Task 4: Projection + samples/events export

**Files:**
- Create: `spikes/sscofs-field/make_samples.py`
- Test: `spikes/sscofs-field/test_project.py`

**Interfaces:**
- Consumes: `mesh/elements.json`, `corpus/*.npz`, `truth/stations.json`.
- Produces: per (station, element within 600 m): `samples/<slug>-e<i>.json` in the exact fitTides shape `[{"t": epochSec, "v": signedKn}]`; per station: `truth/<slug>-events.json` in the harness event shape `[{"eventDate", "qualifier", "value"}]` covering fit-end +28..+35 d. Also `samples/index.json`: `[{"slug", "elem", "samples", "events", "flood", "ebb", "dist_m"}...]` — the run matrix.

- [ ] **Step 1: Write the projection unit test (pure function first)**

```python
# test_project.py — run: uv run --with pytest,numpy pytest -q test_project.py
import numpy as np
from make_samples import project_signed_kn

def test_pure_flood_is_positive():
    # flow toward 100° at 2 m/s, flood axis 100° → +2*1.94384 kn
    u = 2 * np.sin(np.radians(100)); v = 2 * np.cos(np.radians(100))
    assert abs(project_signed_kn(np.array([u]), np.array([v]), 100.0)[0] - 3.88768) < 1e-4

def test_pure_ebb_is_negative():
    u = 1.5 * np.sin(np.radians(280)); v = 1.5 * np.cos(np.radians(280))
    assert project_signed_kn(np.array([u]), np.array([v]), 100.0)[0] < -2.9

def test_cross_axis_is_zero():
    u = 3 * np.sin(np.radians(190)); v = 3 * np.cos(np.radians(190))
    assert abs(project_signed_kn(np.array([u]), np.array([v]), 100.0)[0]) < 1e-9
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd spikes/sscofs-field && uv run --with pytest,numpy pytest -q test_project.py`
Expected: FAIL — `make_samples` has no `project_signed_kn`.

- [ ] **Step 3: Write the script**

```python
#!/usr/bin/env -S uv run --script --with numpy,requests
"""Project box-element u/v onto each truth station's flood axis; export fitTides samples + held-out truth events."""
import glob, json, os, datetime as dt
import numpy as np, requests

MS_TO_KN = 1.94384
IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
CP = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

def project_signed_kn(u, v, flood_deg):
    """signed = speed·cos(dir − flood): the harness/chs-constituents projection (main.swift:189)."""
    speed = np.hypot(u, v) * MS_TO_KN
    direction = np.degrees(np.arctan2(u, v)) % 360.0
    return speed * np.cos(np.radians(direction - flood_deg))

def load_corpus():
    files = sorted(glob.glob("corpus/*.npz"))
    t = np.concatenate([np.load(f)["t"] for f in files])
    u = np.concatenate([np.load(f)["u"] for f in files])
    v = np.concatenate([np.load(f)["v"] for f in files])
    order = np.argsort(t)
    return t[order], u[order], v[order]

def elements_near(els, lat, lon, radius_m=600):
    out = []
    for k, e in enumerate(els):
        d = np.hypot((e["lat"] - lat) * 111320, (e["lon"] - lon) * 111320 * np.cos(np.radians(lat)))
        if d <= radius_m:
            out.append((k, e["i"], d))
    return out

def chs_events(st, start, end):
    q = f"{IWLS}/stations/{st['iwlsId']}/data?time-series-code=wcp1-events&from={start:%Y-%m-%dT%H:%M:%SZ}&to={end:%Y-%m-%dT%H:%M:%SZ}"
    return requests.get(q, timeout=60).json()  # already [{eventDate, qualifier, value}]

def noaa_events(st, start, end):
    r = requests.get(CP, params={"station": st["id"], "product": "currents_predictions",
                                 "begin_date": f"{start:%Y%m%d}", "end_date": f"{end:%Y%m%d}",
                                 "interval": "MAX_SLACK", "units": "english",
                                 "time_zone": "gmt", "format": "json"}, timeout=60).json()
    out = []
    for e in r["current_predictions"]["cp"]:
        vel = float(e["Velocity_Major"])
        kind = ("SLACK" if e["Type"] == "slack" else
                "EXTREMA_FLOOD" if vel > 0 else "EXTREMA_EBB")
        out.append({"eventDate": e["Time"].replace(" ", "T") + ":00Z",
                    "qualifier": kind, "value": abs(vel)})
    return out

def main():
    els = json.load(open("mesh/elements.json"))["elements"]
    stations = json.load(open("truth/stations.json"))
    t, u, v = load_corpus()
    fit_end = dt.datetime.fromtimestamp(t[-1], dt.timezone.utc)
    val = (fit_end + dt.timedelta(days=28), fit_end + dt.timedelta(days=35))
    os.makedirs("samples", exist_ok=True)
    index = []
    for st in stations:
        near = elements_near(els, st["lat"], st["lon"])
        if not near:
            print(f"{st['slug']}: NO ELEMENT within 600 m — record as coverage gap")
            continue
        ev_path = f"truth/{st['slug']}-events.json"
        events = chs_events(st, *val) if st["source"] == "chs" else noaa_events(st, *val)
        json.dump(events, open(ev_path, "w"))
        for k, i, d in near:
            signed = project_signed_kn(u[:, k], v[:, k], st["flood"])
            good = np.isfinite(signed)
            sp = f"samples/{st['slug']}-e{i}.json"
            json.dump([{"t": float(tt), "v": float(vv)} for tt, vv in zip(t[good], signed[good])],
                      open(sp, "w"))
            index.append({"slug": st["slug"], "elem": int(i), "samples": sp, "events": ev_path,
                          "flood": st["flood"], "ebb": st["ebb"], "dist_m": round(d)})
        print(f"{st['slug']}: {len(near)} elements, {len(events)} truth events")
    json.dump(index, open("samples/index.json", "w"), indent=1)

if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the unit test to verify it passes**

Run: `uv run --with pytest,numpy pytest -q test_project.py`
Expected: 3 passed.

- [ ] **Step 5: Run the export (needs Task 2's corpus complete)**

Run: `./make_samples.py`
Expected: one line per station; `samples/index.json` non-empty; spot-check one Active Pass element's samples — signed speeds oscillating roughly ±3–4 kn, and one Dodd element — visibly too small (±1–1.5 kn). That asymmetry appearing here is the spike working.

- [ ] **Step 6: Commit**

```bash
git add spikes/sscofs-field/make_samples.py spikes/sscofs-field/test_project.py
git commit -m "spike(sscofs-field): axis projection (tested) + samples/events export"
```

### Task 5: FitValidation file-input mode

**Files:**
- Modify: `tools/FitValidation/Sources/fit-validation/main.swift` (arg parsing at lines 24-31; add a file-input branch that joins the existing fit/score path at the JSContext setup, main.swift:216)

**Interfaces:**
- Consumes: `--samples <path>` (fitTides sample array), `--events <path>` (event array), `--flood <deg> --ebb <deg>`, `--label <slug-eN>`.
- Produces: the existing report output — per-window fit JSON + a scored verdict line `PASS`/`FAIL` with the five-bar numbers — written to `<cacheDir>/reports/<label>-*.json` and stdout. Exit code 0 = PASS, 1 = FAIL (existing convention).

- [ ] **Step 1: Add the mode**

In `main.swift`, after the existing arg parsing, add a branch: when `--samples` is present, skip IWLS discovery/fetch/projection entirely; decode the samples file into the `(t, v)` pairs the fit loop already consumes (both `projected` and `projected60` — where `projected60` is the trailing 60 days of the file, which for spike input is the whole series); decode the events file into `rawEvents` (`[IwlsEvent]` — the JSON shape matches); take `flood`/`ebb` from the flags; set `name` from `--label`. The fit → `CurrentStation` → scoring code is shared, not duplicated — restructure with `func runFit(samples:events:flood:ebb:label:)` if the current top-level flow makes sharing awkward, but do not change any scoring constant or bar.

```swift
// New flags (follow the existing filter pattern at main.swift:24-25):
//   --samples <file> --events <file> --flood <deg> --ebb <deg> --label <slug>
// Validation window for file mode: derive from the events file's own span
// (min/max eventDate ± half-day pad), NOT from Date() — the corpus decides the epoch.
```

- [ ] **Step 2: Verify against node-control parity (the existing check)**

Run the file mode on an *existing* CHS report's saved bytes: `swift run fit-validation --samples <cacheDir>/reports/dodd-narrows-210d-samples.json --events <a saved events file> --flood <from the earlier run's log> --ebb <...> --label parity-check` and confirm the fit JSON matches the saved `dodd-narrows-210d-fit.json` byte-for-byte. (Any valid events file works here — the fit never reads events; only the score does.) If no cached reports exist locally, run one gate in `--current` mode first to generate them (`swift run fit-validation --current "Dodd Narrows" 49.1367 -123.8183`).
Expected: identical constituents — proving file mode changed I/O only.

- [ ] **Step 3: Run one spike pair end-to-end**

Run: `swift run fit-validation --samples ../../spikes/sscofs-field/samples/<active-pass slug>-e<N>.json --events ../../spikes/sscofs-field/truth/<active-pass slug>-events.json --flood <deg> --ebb <deg> --label active-e<N>` (values from `samples/index.json`).
Expected: a five-bar verdict line. Any result is fine here — this step proves plumbing, not the science.

- [ ] **Step 4: Commit**

```bash
git add tools/FitValidation/Sources/fit-validation/main.swift
git commit -m "tool(fit-validation): file-input mode — fit/score SSCOFS element series on the shipping path"
```

### Task 6: Run matrix + report

**Files:**
- Create: `spikes/sscofs-field/run_matrix.sh`
- Create: `spikes/sscofs-field/report.py`

**Interfaces:**
- Consumes: `samples/index.json`, fit-validation file mode (Task 5).
- Produces: `results/<label>.json` per pair (the verdict numbers, parsed from the report files), `RESULTS.md` — per-station table (best element + nearest element, five bars, PASS/FAIL), the three decision-gate verdicts, and the bundle-size extrapolation.

- [ ] **Step 1: Write the runner**

```bash
#!/bin/bash
# Run fit-validation file mode over every (station, element) pair in samples/index.json.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p results
jq -c '.[]' samples/index.json | while read -r row; do
  slug=$(jq -r .slug <<<"$row"); elem=$(jq -r .elem <<<"$row")
  label="${slug}-e${elem}"
  [ -f "results/${label}.done" ] && continue
  (cd ../../tools/FitValidation && swift run -c release fit-validation \
    --samples "../../spikes/sscofs-field/$(jq -r .samples <<<"$row")" \
    --events  "../../spikes/sscofs-field/$(jq -r .events  <<<"$row")" \
    --flood "$(jq -r .flood <<<"$row")" --ebb "$(jq -r .ebb <<<"$row")" \
    --label "$label") | tee "results/${label}.log" || true
  touch "results/${label}.done"
done
```

- [ ] **Step 2: Write the report generator**

```python
#!/usr/bin/env -S uv run --script --with numpy
"""Aggregate results/*.log into RESULTS.md: per-station verdicts + decision gates + bundle extrapolation."""
import glob, json, re, os
import numpy as np

# Parse the verdict lines fit-validation prints (adapt the regex to the actual
# format once Task 5 output exists — the numbers are: slack med/max, extrema med,
# speed med err, wrongSign fraction, PASS/FAIL).
ROW = re.compile(r"slack med ([\d.]+).*?max ([\d.]+).*?extrema med ([\d.]+).*?speed med ([\d.]+).*?(PASS|FAIL)", re.S)

def parse(log):
    m = ROW.search(open(log).read())
    return None if not m else {"slack_med": float(m[1]), "slack_max": float(m[2]),
                               "ext_med": float(m[3]), "speed_med": float(m[4]),
                               "verdict": m[5]}

def bundle_extrapolation(n_box_elements, box_deg2, k_constituents=(23, 12)):
    # Render region ≈ Salish clip −125.5..−122.0 × 47.0..50.6 (the seamap bbox, #30)
    render_deg2 = (125.5 - 122.0) * (50.6 - 47.0)
    n_render = n_box_elements / box_deg2 * render_deg2   # density extrapolation
    rows = []
    for k in k_constituents:
        bytes_per = k * 2 * (1 + 2 + 2) + 8              # id + f16 amp + f16 phase, ×(u,v), + header
        rows.append((k, n_render, n_render * bytes_per / 1e6))
    return rows

def main():
    idx = {f"{r['slug']}-e{r['elem']}": r for r in json.load(open("samples/index.json"))}
    per_station = {}
    for log in sorted(glob.glob("results/*.log")):
        label = os.path.basename(log)[:-4]
        r = parse(log)
        if r:
            per_station.setdefault(idx[label]["slug"], []).append({**r, **idx[label]})
    els = json.load(open("mesh/elements.json"))
    box = els["box"]; box_deg2 = (box[2] - box[0]) * (box[3] - box[1])
    with open("RESULTS.md", "w") as out:
        out.write("# SSCOFS field spike — results\n\n| station | dist m | slack med | slack max | ext med | speed med | verdict |\n|---|---|---|---|---|---|---|\n")
        for slug, rows in sorted(per_station.items()):
            best = min(rows, key=lambda r: r["speed_med"])
            near = min(rows, key=lambda r: r["dist_m"])
            for tag, r in (("best", best), ("nearest", near)):
                out.write(f"| {slug} ({tag}, e{r['elem']}) | {r['dist_m']} | {r['slack_med']} | {r['slack_max']} | {r['ext_med']} | {r['speed_med']} | {r['verdict']} |\n")
        out.write("\n## Bundle extrapolation\n\n")
        for k, n, mb in bundle_extrapolation(len(els["elements"]), box_deg2):
            out.write(f"- {k} constituents: ~{n:,.0f} render-region elements → **{mb:.1f} MB**\n")
    print(open("RESULTS.md").read())

if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the matrix, then the report**

Run: `./run_matrix.sh && ./report.py`
Expected: RESULTS.md with every truth station represented. Sanity anchors from the 24 h measurement: Active Pass elements should be near the bar; Dodd elements should FAIL decisively on peak speed (multi-knot error). If Dodd *passes*, something is wrong with the projection or element selection — investigate before believing anything else.

- [ ] **Step 4: Commit**

```bash
git add spikes/sscofs-field/run_matrix.sh spikes/sscofs-field/report.py spikes/sscofs-field/RESULTS.md
git commit -m "spike(sscofs-field): run matrix + results report with bundle extrapolation"
```

### Task 7: README + decision

**Files:**
- Create: `spikes/sscofs-field/README.md`

- [ ] **Step 1: Write the README** in the `chs-currents-fit` README's structure: method (corpus, projection, shipping-path fit/score), the bar (copy the five-bar table), results (from RESULTS.md), and a **Decision** section answering the three spec §3 gates explicitly:
  1. do certifiable sub-regions meet the bar? (list which stations/regions)
  2. did Dodd-class stations correctly fail? (the gate must reject)
  3. extrapolated bundle ≤ 40 MB at which constituent count?
  End with the verdict: **Phase B go** / **Plan B (grown patches only)** — quoting the spec's rule that a fail here is a successful spike outcome.

- [ ] **Step 2: Commit**

```bash
git add spikes/sscofs-field/README.md
git commit -m "spike(sscofs-field): method + decision write-up"
```

---

## Self-review notes

- Spec §3 coverage: 60-day box corpus (T2), fit on shipping path (T5), validation vs truth stations on the existing bar (T5/T6), Dodd-must-fail (T6 Step 3 sanity anchor + README gate 2), bundle extrapolation (T6 report), decision (T7). §2/§4/§5 are Phase B/C — deliberately not in this plan.
- API response shapes (IWLS station list, MDAPI, currents_predictions) are best-effort from documented use; each task's verify step says what to check and where the known-good reference is. The harness (`main.swift`) is the authority for IWLS shapes.
- The `hour_urls` cycle→valid-time offset is flagged as verify-then-fix (T2 Step 2) rather than asserted — the file's own time variable is the truth.
- `report.py`'s verdict regex is explicitly marked adapt-to-actual-output; parity check (T5 Step 2) pins the science before any aggregation runs.
