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
