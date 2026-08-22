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
