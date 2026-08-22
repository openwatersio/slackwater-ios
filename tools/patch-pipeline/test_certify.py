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


RECIP_DOC = {
    "slug": "tacoma-narrows",
    "sections": [{"center": [0.0, 0.0]}, {"center": [0.0, 0.01]}, {"center": [0.0, 0.02]}],
    "scales": [1.0, 0.5, 0.25],          # normalized to section 0 (the series anchor)
    "kept_range": [0, 2],
    "section_spacing_m": 1500,
}
RECIP_INPUTS = {
    "check_stations": [{"station_id": "B", "lat": 0.02, "lon": 0.0,
                        "flood_deg": 213.5, "ebb_deg": 33.5}],
    "reciprocal_check": {"anchor_station_id": "B",
                         "target": {"station_id": "A", "lat": 0.0, "lon": 0.0,
                                    "flood_deg": 208.5, "ebb_deg": 28.5}},
}

def test_reciprocal_renormalizes_to_the_reciprocal_anchor():
    from certify_patch import reciprocal_spec
    spec = reciprocal_spec(RECIP_DOC, RECIP_INPUTS)
    # scale used = scales[target section] / scales[reciprocal anchor section]
    assert spec["scale"] == 4.0                       # 1.0 / 0.25
    assert spec["anchor_id"] == "B"
    assert spec["target"]["station_id"] == "A"

def test_reciprocal_label_format():
    from certify_patch import reciprocal_spec
    assert reciprocal_spec(RECIP_DOC, RECIP_INPUTS)["label"] == "tacoma-narrows-recip-A"

def test_reciprocal_scale_is_positive_and_preserves_sign():
    from certify_patch import reciprocal_spec
    spec = reciprocal_spec(RECIP_DOC, RECIP_INPUTS)
    out = scale_samples([{"t": 1, "v": 2.0}, {"t": 2, "v": -2.0}], spec["scale"])
    assert [s["v"] for s in out] == [8.0, -8.0]

def test_no_reciprocal_check_is_none():
    from certify_patch import reciprocal_spec
    assert reciprocal_spec(RECIP_DOC, {"check_stations": []}) is None
