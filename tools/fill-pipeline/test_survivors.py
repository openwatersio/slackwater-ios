# test_survivors.py — run: uv run --with pytest,numpy pytest -q test_survivors.py
#
# Only the new glue logic gets tests here (per task-4-brief.md's steps):
# §4a grading (certify.py) and the numpy prefilter (prune_proof.py) are
# imported, not reimplemented, and already have their own test suites.
import json

import numpy as np

from survivors import build_survivors, load_done, r2_from_rms


def test_r2_from_rms_matches_direct_computation():
    # A tiny synthetic series where SS_res/SS_tot can be hand-checked.
    values = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float32)
    n = len(values)
    mean = values.mean()
    ss_tot = float(np.sum((values - mean) ** 2))
    # Pick an rms so ss_res is exactly half of ss_tot -> r2 == 0.5.
    rms = (0.5 * ss_tot / n) ** 0.5
    assert abs(r2_from_rms(rms, n, values) - 0.5) < 1e-9


def test_r2_from_rms_zero_residual_is_one():
    values = np.array([1.0, 1.0, 1.0, 5.0], dtype=np.float32)
    assert r2_from_rms(0.0, len(values), values) == 1.0


def test_r2_from_rms_constant_series_is_zero_not_divide_by_zero():
    # ss_tot == 0 for a constant series -- must not raise or return NaN/inf.
    values = np.array([2.0, 2.0, 2.0], dtype=np.float32)
    assert r2_from_rms(0.1, len(values), values) == 0.0


def test_load_done_reads_existing_pairs(tmp_path):
    path = tmp_path / "fits.jsonl"
    path.write_text(
        json.dumps({"elem": 1, "axis": "u", "rms": 0.1}) + "\n"
        + json.dumps({"elem": 1, "axis": "v", "rms": 0.2}) + "\n"
        + json.dumps({"elem": 2, "axis": "u", "error": "boom"}) + "\n"
    )
    done = load_done(str(path))
    assert done == {(1, "u"), (1, "v"), (2, "u")}
    # untouched -- all lines were complete, nothing to truncate
    assert path.read_text().count("\n") == 3


def test_load_done_truncates_torn_trailing_line(tmp_path):
    path = tmp_path / "fits.jsonl"
    good_line = json.dumps({"elem": 1, "axis": "u", "rms": 0.1}) + "\n"
    torn_line = '{"elem": 2, "axis": "u", "rms": 0.05, "const'  # killed mid-write
    path.write_bytes((good_line + torn_line).encode())

    done = load_done(str(path))

    assert done == {(1, "u")}
    # the torn line is gone -- a resumed run must be able to re-append elem 2
    assert path.read_text() == good_line


def test_load_done_missing_file_returns_empty_set(tmp_path):
    assert load_done(str(tmp_path / "nope.jsonl")) == set()


def test_build_survivors_applies_floor_both_axes(tmp_path):
    fits_path = tmp_path / "fits.jsonl"
    # elem 1: both axes clear 0.8 -> survivor
    # elem 2: u clears, v doesn't -> dropped (floor is BOTH axes)
    # elem 3: an error row on v -> dropped (never completes both axes)
    n = 4
    values = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float32)
    ss_tot = float(np.sum((values - values.mean()) ** 2))

    def rms_for_r2(r2):
        return (( 1 - r2) * ss_tot / n) ** 0.5

    rows = [
        {"elem": 1, "axis": "u", "rms": rms_for_r2(0.95), "constituents": [{"name": "M2", "amplitude": 0.5, "phase": 10}]},
        {"elem": 1, "axis": "v", "rms": rms_for_r2(0.90), "constituents": [{"name": "K1", "amplitude": 0.3, "phase": 20}]},
        {"elem": 2, "axis": "u", "rms": rms_for_r2(0.95), "constituents": []},
        {"elem": 2, "axis": "v", "rms": rms_for_r2(0.10), "constituents": []},
        {"elem": 3, "axis": "u", "rms": rms_for_r2(0.95), "constituents": []},
        {"elem": 3, "axis": "v", "error": "fit needs at least two samples"},
    ]
    fits_path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")

    t = np.zeros(n)  # only len(t) matters to build_survivors
    shortlist_elems = [1, 2, 3]
    shortlist_cols = [0, 1, 2]
    u_kn = np.stack([values, values, values], axis=1)
    v_kn = np.stack([values, values, values], axis=1)

    survivors, n_error, unseparable = build_survivors(
        str(fits_path), shortlist_elems, shortlist_cols, t, u_kn, v_kn)

    assert [s["i"] for s in survivors] == [1]
    assert survivors[0]["constituents_u"] == [{"name": "M2", "amplitude": 0.5, "phase": 10}]
    assert survivors[0]["constituents_v"] == [{"name": "K1", "amplitude": 0.3, "phase": 20}]
    assert survivors[0]["r2_u"] > 0.8 and survivors[0]["r2_v"] > 0.8
    assert n_error == 1


def test_build_survivors_passes_through_unseparable_for_reporting(tmp_path):
    fits_path = tmp_path / "fits.jsonl"
    n = 4
    values = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float32)
    ss_tot = float(np.sum((values - values.mean()) ** 2))
    rms = ((1 - 0.99) * ss_tot / n) ** 0.5
    rows = [
        {"elem": 1, "axis": "u", "rms": rms, "constituents": [], "unseparable": ["S2/T2"]},
        {"elem": 1, "axis": "v", "rms": rms, "constituents": [], "unseparable": ["S2/T2"]},
    ]
    fits_path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")

    t = np.zeros(n)
    u_kn = values.reshape(-1, 1)
    v_kn = values.reshape(-1, 1)
    survivors, n_error, unseparable = build_survivors(
        str(fits_path), [1], [0], t, u_kn, v_kn)

    assert unseparable == ["S2/T2"]
