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
