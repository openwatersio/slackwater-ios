# test_pack.py — run: uv run --with pytest pytest -q test_pack.py
#
# (a) round-trip: pack a synthetic 3-element survivors+mesh fixture, parse it
#     back with a tiny pure-python reader (below) that mirrors the binary
#     layout documented in pack.py's module docstring / task-5-brief.md
#     independently of pack.py's own pack_element -- so a bug shared between
#     writer and reader wouldn't hide here. Assert verts/constituents match
#     within f16 tolerance.
# (b) the 40 MB size gate fires -- forced via a tiny max_bytes rather than
#     actually generating 40 MB of synthetic elements (same code path, far
#     less test data; brief allows either). Gate is an explicit
#     if/SystemExit, not a bare `assert`, so `python -O` can't strip it.
# (c) energy floor: per-axis, per-element -- an amp below both this
#     element's own floors is dropped, one above ships.
# (d) unknown constituent name is a hard error, never a silent drop.
#
# Phase tolerance in these tests is 0.25 deg -- f16's worst-case ULP near
# 360 deg (pack.py's build_header/precision), not an arbitrary "close
# enough" number. The round-trip fixture below deliberately phases M2/K1
# near that boundary (359.9 / 0.1) so the worst case is what's exercised.
import json
import struct

import pytest

from pack import BASIS_NAMES, pack, prune_axis

BBOX = [-125.5, 47.0, -122.0, 50.6]


def _write_fixture(tmp_path, survivors, mesh, stations=None,
                    corpus_days=("20260101", "20260110")):
    corpus_dir = tmp_path / "corpus"
    corpus_dir.mkdir()
    for d in corpus_days:
        (corpus_dir / f"{d}.npz").write_bytes(b"")  # filenames only -- pack.py never opens these
    survivors_path = tmp_path / "survivors.json"
    mesh_path = tmp_path / "mesh.json"
    stations_path = tmp_path / "stations.json"
    survivors_path.write_text(json.dumps(survivors))
    mesh_path.write_text(json.dumps(mesh))
    stations_path.write_text(json.dumps(stations or [{"slug": "test-station"}]))
    return str(survivors_path), str(mesh_path), str(stations_path), str(corpus_dir)


def _read_bundle(bin_bytes, header):
    """Tiny pure-python reader, deliberately independent of pack.pack_element."""
    offsets = header["offsets"]
    out = []
    for k in range(header["element_count"]):
        chunk = bin_bytes[offsets[k]:offsets[k + 1]]
        pos = 0
        nverts = chunk[pos]
        pos += 1
        verts = []
        for _ in range(nverts):
            lon, lat = struct.unpack_from("<ff", chunk, pos)
            pos += 8
            verts.append((lon, lat))
        offset_u, offset_v = struct.unpack_from("<ee", chunk, pos)
        pos += 4
        axes = []
        for _ in range(2):  # u then v
            n = chunk[pos]
            pos += 1
            axis = []
            for _ in range(n):
                cid, amp, phase = struct.unpack_from("<Bee", chunk, pos)
                pos += 5
                axis.append({"id": cid, "amplitude": amp, "phase": phase})
            axes.append(axis)
        out.append({"verts": verts, "offset_u": offset_u, "offset_v": offset_v,
                    "u": axes[0], "v": axes[1]})
    return out


def _mk_element(i, lon=-123.0, lat=48.7, offset_u=0.0, offset_v=0.0):
    verts = [[lon, lat], [lon + 0.01, lat], [lon, lat + 0.01]]
    survivor = {
        "i": i,
        "constituents_u": [
            # phase 359.9 sits right at the f16 wraparound boundary --
            # worst-case ULP territory, not a comfortable mid-range value.
            {"name": "M2", "amplitude": 1.0, "phase": 359.9},  # floor = max(2%, 0.005) = 0.02 -> kept
            {"name": "S2", "amplitude": 0.003, "phase": 10.0},  # below 0.02 -> dropped
        ],
        "constituents_v": [
            {"name": "K1", "amplitude": 0.5, "phase": 0.1},  # same boundary, other side of 0/360
        ],
        "r2_u": 0.95,
        "r2_v": 0.9,
        "offset_u": offset_u,
        "offset_v": offset_v,
    }
    mesh_el = {"i": i, "lon": lon, "lat": lat, "verts": verts}
    return survivor, mesh_el


def _fixture_3_elements():
    els, mesh_els = [], []
    # Element 20 carries a nonzero Z0 offset -- one element on-floor-zero,
    # one off, so the round-trip test can't pass by accident on an
    # all-zeros encode/decode.
    offsets = {10: (0.0, 0.0), 20: (-0.65, 0.27), 30: (0.0, 0.0)}
    for i in (10, 20, 30):
        e, m = _mk_element(i, lon=-123.0 + i, lat=48.7,
                            offset_u=offsets[i][0], offset_v=offsets[i][1])
        els.append(e)
        mesh_els.append(m)
    survivors = {"D_m": 3000, "counts": {"certified": 3, "survivors": 3}, "elements": els}
    mesh = {"file": "https://example.test/fields.nc", "bbox": BBOX, "elements": mesh_els}
    return survivors, mesh


def test_round_trip(tmp_path):
    survivors, mesh = _fixture_3_elements()
    paths = _write_fixture(tmp_path, survivors, mesh)
    bin_bytes, header = pack(*paths, generated="2026-08-20T00:00:00+00:00")

    assert header["format_version"] == 1
    assert header["region"] == "salish"
    assert header["element_count"] == 3
    assert header["generated"] == "2026-08-20T00:00:00+00:00"
    assert header["D_m"] == 3000
    assert header["constituents"]["0"] == BASIS_NAMES[0]
    assert header["bin_sha256"]
    assert header["corpus_window"] == {"start": "2026-01-01", "end": "2026-01-10"}
    assert header["precision"]["phase_deg_worst_ulp"] == 0.25
    # station_set.path is basename-only, never the packer's local filesystem
    # path (tmp_path here is absolute -- a regression would leak it verbatim
    # into a committed artifact).
    assert header["station_set"]["path"] == "stations.json"
    assert "/" not in header["station_set"]["path"]
    assert header["offset_note"]
    PHASE_TOL = header["precision"]["phase_deg_worst_ulp"]

    parsed = _read_bundle(bin_bytes, header)
    assert len(parsed) == 3
    for e, m, p in zip(survivors["elements"], mesh["elements"], parsed):
        for (vlon, vlat), (plon, plat) in zip(m["verts"], p["verts"]):
            assert plon == pytest.approx(vlon, abs=1e-4)
            assert plat == pytest.approx(vlat, abs=1e-4)

        # Z0 offset round-trips through f16 (~0.1% relative, same precision
        # as amplitude) -- element 20's nonzero offset and elements 10/30's
        # zero offset both must survive.
        assert p["offset_u"] == pytest.approx(e["offset_u"], abs=5e-3)
        assert p["offset_v"] == pytest.approx(e["offset_v"], abs=5e-3)

        # S2 (amp 0.003) is below its axis floor and must not survive.
        assert len(p["u"]) == 1
        assert p["u"][0]["id"] == BASIS_NAMES.index("M2")
        assert p["u"][0]["amplitude"] == pytest.approx(1.0, abs=5e-3)
        assert p["u"][0]["phase"] == pytest.approx(359.9, abs=PHASE_TOL)

        assert len(p["v"]) == 1
        assert p["v"][0]["id"] == BASIS_NAMES.index("K1")
        assert p["v"][0]["amplitude"] == pytest.approx(0.5, abs=5e-3)
        assert p["v"][0]["phase"] == pytest.approx(0.1, abs=PHASE_TOL)


def test_size_gate_fires(tmp_path):
    survivors, mesh = _fixture_3_elements()
    paths = _write_fixture(tmp_path, survivors, mesh)
    with pytest.raises(SystemExit, match="exceeds"):
        pack(*paths, max_bytes=1)


def test_energy_floor_drops_below_keeps_above():
    axis = [
        {"name": "M2", "amplitude": 1.0, "phase": 0.0},   # floor = max(0.02*1.0, 0.005) = 0.02 -> kept
        {"name": "S2", "amplitude": 0.01, "phase": 0.0},  # 0.01 < 0.02 -> dropped
    ]
    kept = prune_axis(axis)
    assert [c["name"] for c in kept] == ["M2"]


def test_energy_floor_uses_min_kn_when_2pct_is_smaller():
    # axis max is tiny (0.1 kn); 2% of that is 0.002, below the 0.005 kn
    # absolute floor, so the floor is pinned at 0.005 kn, not 0.002.
    axis = [
        {"name": "M2", "amplitude": 0.1, "phase": 0.0},     # 2% of max -> floor pinned to 0.005
        {"name": "S2", "amplitude": 0.0049, "phase": 0.0},  # just under 0.005 -> dropped
        {"name": "N2", "amplitude": 0.005, "phase": 0.0},   # exactly at 0.005 -> kept
    ]
    kept = prune_axis(axis)
    assert [c["name"] for c in kept] == ["M2", "N2"]


def test_unknown_constituent_is_hard_error(tmp_path):
    survivors, mesh = _fixture_3_elements()
    survivors["elements"][0]["constituents_u"].append(
        {"name": "BOGUS", "amplitude": 1.0, "phase": 0.0})
    paths = _write_fixture(tmp_path, survivors, mesh)
    with pytest.raises(ValueError, match="BOGUS"):
        pack(*paths)


def test_r2_below_floor_is_hard_error(tmp_path):
    # survivors.json is supposed to already be R^2-filtered upstream (task 4)
    # -- pack.py re-checks at the trust boundary rather than trusting it blind.
    survivors, mesh = _fixture_3_elements()
    survivors["elements"][0]["r2_u"] = 0.5
    paths = _write_fixture(tmp_path, survivors, mesh)
    with pytest.raises(ValueError, match="r2"):
        pack(*paths)
