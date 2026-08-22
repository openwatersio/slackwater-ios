#!/usr/bin/env -S uv run --script --with numpy
"""Slackwater patch-pipeline — bundle pack tool (grown-patches spec §7.3 /
task-6-brief.md). Packs passes/<slug>.json (kept_range-narrowed sections,
sections.py's output) into Slackwater/Resources/patches-<region>.bin plus a
sidecar JSON header.

Binary layout, little-endian, cells concatenated per patch, fixed 30-byte
cells (no per-cell offsets needed -- fixed size, and the sidecar's per-patch
`offset` + `cell_count` locate every patch's byte range):

    per cell:
        3 x (f32 lon, f32 lat)      # triangle vertices (24 B)
        f16 scale                   # A(anchor)/A(here)
        f16 bearing_deg             # flood set direction
        f16 width_m                 # local channel width (channel-2 sample extent)

Cells: for each kept section interval [i, i+1] (kept_range's lo..hi-1), the
quad (left_i, right_i, right_{i+1}, left_{i+1}) splits into two triangles --
(left_i, right_i, right_{i+1}) and (left_i, right_{i+1}, left_{i+1}) -- both
carrying the same interval-level scale/bearing/width: cell scale =
mean(scales[i], scales[i+1]), bearing = bearing between section centers
(sections.py's own _bearing_deg, imported rather than re-derived), width =
mean(width_m[i], width_m[i+1]). A kept_range with a single section
(lo == hi, e.g. deception-pass) has no interval and ships zero cells --
header present, zero bytes, not a special-cased omission.
"""
import glob
import hashlib
import json
import os
import struct
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sections import _bearing_deg

MAX_BYTES = 1_048_576


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    with open(path, "rb") as fh:
        return sha256_bytes(fh.read())


def _patch_cells(doc):
    """Cells for one pass doc's kept_range, per this module's docstring."""
    sections, scales = doc["sections"], doc["scales"]
    lo, hi = doc["kept_range"]
    cells = []
    for i in range(lo, hi):
        s0, s1 = sections[i], sections[i + 1]
        scale = (scales[i] + scales[i + 1]) / 2.0
        bearing = _bearing_deg(s0["center"], s1["center"])
        width = (s0["width_m"] + s1["width_m"]) / 2.0
        for tri in ((s0["left"], s0["right"], s1["right"]),
                    (s0["left"], s1["right"], s1["left"])):
            buf = bytearray()
            for lon, lat in tri:
                buf += struct.pack("<ff", lon, lat)
            buf += struct.pack("<eee", scale, bearing, width)
            cells.append(bytes(buf))
    return cells


def pack_patches(pass_docs, max_bytes=MAX_BYTES, generated=None):
    """Pure core: no file I/O beyond what pass_docs already carry. Returns
    (bin_bytes, header_dict). `generated` is injectable so tests never race
    the clock (mirrors fill-pipeline/pack.py's pack())."""
    buf = bytearray()
    patches = []
    for doc in pass_docs:
        cells = _patch_cells(doc)
        offset = len(buf)
        for c in cells:
            buf += c
        patches.append({
            "id": doc["slug"],
            "anchor": {"provider": doc["anchor"]["provider"],
                       "station_id": doc["anchor"]["station_id"]},
            "cell_count": len(cells),
            "offset": offset,
        })
    bin_bytes = bytes(buf)
    # Explicit check + SystemExit, not a bare `assert` -- survives `python -O`.
    if len(bin_bytes) > max_bytes:
        raise SystemExit(
            f"bundle {len(bin_bytes)} bytes exceeds {max_bytes} byte budget "
            f"({len(bin_bytes) / 1e6:.2f} MB vs {max_bytes / 1e6:.2f} MB) -- "
            "shrink the patch set before shipping")
    header = {
        "format_version": 1,
        "region": "salish",
        "generated": generated or datetime.now(timezone.utc).isoformat(),
        "bin_sha256": sha256_bytes(bin_bytes),
        "patches": patches,
    }
    return bin_bytes, header


def main():
    pass_docs, source_shas = [], {}
    for path in sorted(glob.glob("passes/*.json")):
        doc = json.load(open(path))
        pass_docs.append(doc)
        source_shas[doc["slug"]] = sha256_file(path)

    bin_bytes, header = pack_patches(pass_docs)
    for p in header["patches"]:
        p["source_sha256"] = source_shas[p["id"]]

    out_dir = "../../Slackwater/Resources"
    os.makedirs(out_dir, exist_ok=True)
    with open(f"{out_dir}/patches-salish.bin", "wb") as fh:
        fh.write(bin_bytes)
    with open(f"{out_dir}/patches-salish.json", "w") as fh:
        json.dump(header, fh, indent=1)
    kb = len(bin_bytes) / 1024
    print(f"packed {len(header['patches'])} patches, {len(bin_bytes)} bytes "
          f"({kb:.1f} KB) -> {out_dir}/patches-salish.bin + .json")
    for p in header["patches"]:
        print(f"  {p['id']}: {p['cell_count']} cells, offset {p['offset']}")


if __name__ == "__main__":
    main()
