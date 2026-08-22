# patch-pipeline

Produces `passes/<slug>.json` — refined thalweg, perpendicular cross-sections,
A(x) at MWL, and continuity scales A(anchor)/A(x) — for a hand-authored
`inputs/<slug>.json` plus bathymetry tiles. Design: grown-patches spec §2.

Everything below runs from `tools/patch-pipeline/`. `data/` (tile cache) is
gitignored; only `inputs/*.json` and `passes/*.json` are committed.

## What it produces

`sections.py <slug>` reads `inputs/<slug>.json` + `data/tiles/<slug>/*.tif(f)`
(with a `MANIFEST.json` beside them) and writes `passes/<slug>.json`: the
thalweg refined to the deepest connected path, one cross-section per
`section_spacing_m` along it (width, area at MWL, left/right bank points),
and per-section continuity scales relative to the anchor station's section.

Thalweg refinement is two passes: build sections perpendicular to the
hand-drawn seed, recenter each on its deepest sample, then rebuild sections
perpendicular to the refined polyline once. "Connected" is three constraints
on that recentering, and dropping any of them puts sections *along* the
channel instead of across it:

- a section measures the contiguous wet run containing **its own centre**, so
  a station beside an island cannot measure the water on the far side of it;
- the deepest sample only moves the thalweg when it beats the seed point by
  `MIN_RELIEF_M` — in a flat reach "deepest" is a metre of noise that flips
  sides between stations, and there the hand-drawn seed is the centreline;
- the lateral move per station is capped at `MAX_SLEW x section_spacing_m`,
  then the polyline is smoothed (moving average, window 3). `build_pass(inputs, depth_at)`
is the pure, testable core — no file or tile I/O — see `test_sections.py`
for a synthetic V-channel with analytically known areas.

## Tile acquisition

Tiles are never committed (NONNA clause 7 / BlueTopo per-tile contributor
check) — `data/tiles/<slug>/` is gitignored and disposable; `MANIFEST.json`'s
sha256 + provenance is copied into the committed pass artifact instead.

- **BlueTopo** (US, `tile_value: "elevation"`, metres negative-down): browse
  the tile index at
  `https://noaa-ocs-nationalbathymetry-pds.s3.amazonaws.com/index.html#BlueTopo/`,
  download the tile(s) covering the pass bbox, and record the band-2
  contributor check in `MANIFEST.json`'s `contributor` field.
  **BlueTopo has no Pacific Northwest coverage** (checked 2026-08-21: the
  tile scheme geopackage under `BlueTopo/_BlueTopo_Tile_Scheme/` has zero
  delivered tiles north of 42 N, and UTM-10 deliveries stop at the
  California/Oregon border). For WA passes use the NOAA **Navigation Test and
  Evaluation** BAG surfaces in the *same* bucket instead — same agency (Office
  of Coast Survey, National Bathymetric Source), 4 m, MLLW, elevation-up, so
  still `tile_value: "elevation"`. Find them via
  `Test-and-Evaluation/Navigation_Test_and_Evaluation/_Navigation_Tile_Scheme/*.gpkg`
  (fields `BAG`, `BAG_SHA256`), verify the published sha256, then
  `gdal_translate -b 1` the `.bag` to a `.tiff` (this script only reads
  GeoTIFFs). A BAG has no contributor band — band 2 is uncertainty — so the
  per-tile provenance check is the ISO-19139 block:
  `gdalinfo -mdd xml:BAG <tile>.bag`.
- **NONNA** (Canada, `tile_value: "depth"`, metres positive-down): register
  at the CHS NONNA portal `https://data.chs-shc.ca`, accept the licence, and
  download NONNA-10 GeoTIFF tiles for the pass. Note the licence acceptance
  date in `MANIFEST.json`.

`MANIFEST.json` shape:

```json
{"tiles": [{"file": "<name>.tiff", "source_url": "https://...", "sha256": "<sha256 of file>",
            "retrieved": "2026-08-22", "contributor": "checked: <band-2 contributor / licence note>"}]}
```

## Run order

```sh
./sections.py <slug>        # passes/<slug>.json
./sensitivity.py <slug>     # placement-error truncation sweep
./certify_patch.py          # grading gate
./pack.py                   # committed bundle
```

Only `sections.py` exists so far; the rest are later tasks in this pipeline.

## Drift check

Re-run `./sections.py <slug>` — `git diff passes/` must be empty apart from
the `generated` timestamp field. A non-timestamp diff means either the tiles
changed (re-check `MANIFEST.json` hashes) or the geometry code did.

## Tests

```sh
uv run --with pytest,numpy,rasterio pytest -q test_sections.py
```
