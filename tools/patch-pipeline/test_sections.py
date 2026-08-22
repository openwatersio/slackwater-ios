# tools/patch-pipeline/test_sections.py — run: uv run --with pytest,numpy,rasterio pytest -q test_sections.py
import math
import numpy as np
from sections import build_pass, _walk

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

def test_walk_keeps_spacing_across_segment_boundary():
    # Regression: a segment boundary must not reset the walk's phase. Two
    # unevenly-spaced segments (995 m, 1300 m) at 500 m spacing, straight
    # north so distance is pure lat*M_PER_DEG_LAT. The first segment's
    # leftover carry (-495 m, i.e. the next mark falls 5 m into segment 2)
    # must persist -- a carry reset to 0 at the boundary produces one gap
    # of ~995 m (~2x spacing) where a correct walk holds every gap at 500 m.
    spacing = 500.0
    seg1_m, seg2_m = 995.0, 1300.0
    lat1 = seg1_m / M_PER_DEG_LAT
    lat2 = lat1 + seg2_m / M_PER_DEG_LAT
    stations = _walk([[0.0, 0.0], [0.0, lat1], [0.0, lat2]], spacing)
    cumulative = [lat * M_PER_DEG_LAT for _, lat in stations]
    gaps = [b - a for a, b in zip(cumulative, cumulative[1:])]
    assert all(gap <= 1.5 * spacing for gap in gaps), gaps

def test_flood_bearing_assert():
    bad = synthetic_inputs()
    bad["anchor"]["flood_deg"] = 180.0  # seed drawn south->north = flood 0; reversed must raise
    try:
        build_pass(bad, synthetic_depth)
        assert False, "expected SystemExit on reversed thalweg"
    except SystemExit:
        pass

def flat_reach_inputs():
    # Wide flat-bottomed reach: 2000 m wide, ~50 m everywhere, with a 0.5 m
    # cross-channel tilt that flips side every ~1.2 km. "Deepest" is noise here.
    return {
        "slug": "flat",
        "anchor": {"provider": "noaa", "station_id": "FLAT1", "lat": 0.0, "lon": 0.0,
                   "flood_deg": 0.0, "spring_max_kn": 4.0},
        "thalweg_seed": [[0.0002, -0.013], [-0.0002, 0.013]],
        "section_spacing_m": 250,
        "max_half_width_m": 2000,
        "cd_to_mwl_m": 0.0,
        "tile_value": "depth",
        "ends": {"start": "test", "end": "test"},
        "check_stations": [],
    }

def flat_reach_depth(lon, lat):
    x = lon * M_PER_DEG_LAT
    y = lat * M_PER_DEG_LAT
    if abs(x) > 1000:
        return float("nan")
    return 50.0 + 0.5 * math.sin(y / 400.0) * (x / 1000.0)

def test_flat_reach_sections_stay_perpendicular():
    # A metre of bottom noise must not swing the thalweg across the channel:
    # every section stays within +/-60 deg of the seed's bearing (~0), and none
    # saturates at 2 * max_half_width_m (the along-channel signature).
    inp = flat_reach_inputs()
    out = build_pass(inp, flat_reach_depth)
    for i, sec in enumerate(out["sections"]):
        off = abs((sec["bearing_deg"] + 180) % 360 - 180)  # vs seed bearing ~0
        assert off <= 60, (i, sec["bearing_deg"], off)
        assert sec["width_m"] < 2 * inp["max_half_width_m"], (i, sec["width_m"])

def _write_tile(path, lon0, lat0, values, nodata=-999999.0):
    import rasterio
    from rasterio.transform import from_origin
    h, w = values.shape
    res = 0.001
    with rasterio.open(path, "w", driver="GTiff", height=h, width=w, count=1,
                       dtype="float32", crs="EPSG:4326", nodata=nodata,
                       transform=from_origin(lon0, lat0 + h * res, res, res)) as dst:
        dst.write(values.astype("float32"), 1)

def test_tile_depth_falls_through_seam_nodata(tmp_path):
    # Two overlapping tiles, as adjacent survey tiles really are. "a" is read
    # first (sorted) and holds nodata over the seam; "b" holds real data there.
    from sections import tile_depth_fn
    seam_lon, seam_lat = 0.0100, 0.0050
    a = np.full((20, 20), -10.0)          # tile a: lon 0.000..0.020
    a[:, 8:] = -999999.0                  # nodata over the seam and east of it
    _write_tile(str(tmp_path / "a.tif"), 0.000, 0.000, a)
    b = np.full((20, 20), -30.0)          # tile b: lon 0.008..0.028, all valid
    _write_tile(str(tmp_path / "b.tif"), 0.008, 0.000, b)

    depth_at = tile_depth_fn(str(tmp_path), "elevation", 2.0)
    assert depth_at(seam_lon, seam_lat) == 32.0        # b's value, not NaN
    assert depth_at(0.0020, seam_lat) == 12.0          # a's own valid area
    assert math.isnan(depth_at(5.0, 5.0))              # no covering tile

def test_section_measures_the_channel_the_station_is_in():
    # Two parallel channels split by an island (Pass Island, Deception). The
    # north one is deeper; a station in the south one must still measure the
    # south one -- growing the wet run from the deepest sample walks the
    # thalweg across the island into water it is not connected to.
    from sections import _section
    def depth(lon, lat):
        x = lon * M_PER_DEG_LAT
        if abs(x) < 105:
            return 30.0            # south channel, 200 m wide, station sits here
        if 245 < x < 655:
            return 60.0            # north channel, 400 m wide and deeper
        return float("nan")        # island / shore
    left, right, width, area, deep_off, deep_d = _section([0.0, 0.0], 0.0, 900, depth)
    assert width == 200.0, width
    assert area == 6000.0, area
    assert deep_d == 30.0 and abs(deep_off) <= 100.0, (deep_d, deep_off)

def flared_inputs():
    # Straight channel, flat 50 m bottom, 1000 m wide up to y = +1750 m and
    # 4000 m wide north of it -- a mouth flare. Anchor at y = 0 (the throat).
    return {
        "slug": "flared",
        "anchor": {"provider": "noaa", "station_id": "FLARE1", "lat": 0.0, "lon": 0.0,
                   "flood_deg": 0.0, "spring_max_kn": 4.0},
        "thalweg_seed": [[0.0, -3000.0 / M_PER_DEG_LAT], [0.0, 5000.0 / M_PER_DEG_LAT]],
        "section_spacing_m": 500,
        "max_half_width_m": 2500,
        "cd_to_mwl_m": 0.0,
        "tile_value": "depth",
        "ends": {"start": "test", "end": "test"},
        "check_stations": [],
    }

def flared_depth(lon, lat):
    x = lon * M_PER_DEG_LAT
    y = lat * M_PER_DEG_LAT
    half = 500.0 if y < 1750.0 else 2000.0
    return 50.0 if abs(x) <= half else float("nan")

def test_kept_range_stops_at_the_flare():
    # Spec 3: walking outward from the anchor, the patch ends at the first
    # section wider than FLARE x the throat width. 4000 m > 1.3 x 1000 m.
    out = build_pass(flared_inputs(), flared_depth)
    lo, hi = out["kept_range"]
    assert lo == 0, lo                                  # no flare southward
    assert hi < len(out["sections"]) - 1, (hi, len(out["sections"]))
    for s in out["sections"][lo:hi + 1]:
        assert s["width_m"] <= 1.3 * 1000.0, s
    assert out["sections"][hi + 1]["width_m"] > 1.3 * 1000.0
    assert out["sections"][hi]["center"][1] * M_PER_DEG_LAT == 1500.0

def test_flare_ratio_override_widens_the_bounds():
    inp = flared_inputs()
    inp["flare_ratio"] = 5.0                            # 4000 m < 5 x 1000 m
    out = build_pass(inp, flared_depth)
    assert out["kept_range"] == [0, len(out["sections"]) - 1]
    assert out["flare_ratio"] == 5.0
