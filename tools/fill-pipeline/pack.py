#!/usr/bin/env -S uv run --script
"""Slackwater fill-pipeline — bundle pack tool (format v1). Packs
data/survivors.json (Task 4's output; join key `i` = full-mesh element
index) + data/mesh.json into Slackwater/Resources/fill-<region>.bin +
sidecar JSON header, per fill-phase-b-design.md §3 / task-5-brief.md.

Binary layout, little-endian, elements concatenated (no per-file header --
the offsets table lives in the sidecar JSON, which is read once at bundle
load anyway, so a fixed head array would only duplicate it):

    per element:
        u8 vert_count (=3)
        3 x (f32 lon, f32 lat)
        u8 nu (kept u-constituent count)
        nu x (u8 constituent_id, f16 amplitude, f16 phase)
        u8 nv (kept v-constituent count)
        nv x (same)

Energy floor is applied HERE, at pack time, per-axis INDEPENDENTLY:
constituent kept on axis X iff amp >= max(2% of *this element's own*
axis-X max amplitude, 0.005 kn). u and v get separate kept lists in the
shipped format, so there is no reason to couple them at pack time.

This deliberately differs from composite-design.md §10's bundle-sizing
estimate (spikes/sscofs-field/prune_proof.py:energy_floor_keep), which
keeps a constituent for BOTH axes if EITHER axis clears -- a sizing-time
simplification (one shared kept-set is cheaper to reason about when
estimating a byte budget), not the shipped rule. Pruning independently
here only ever ships fewer bytes than that estimate assumed.
"""
import argparse
import glob
import hashlib
import json
import os
import struct
from datetime import datetime, timezone

# 23-name shipping basis, canonical order pinned to the constituent id
# table below. Sourced verbatim from spikes/sscofs-field/prune_proof.py:34-35
# (BASIS_NAMES) -- that script already proved all 23 resolve against
# Slackwater/Resources/chs-bundle.js's own embedded defineConstituent(...)
# records (node vm, no fallback to a second-sourced hand-typed table).
# Reused rather than re-derived so there is exactly one basis-order list in
# the repo.
BASIS_NAMES = [
    "M2", "S2", "N2", "K2", "K1", "O1", "P1", "Q1", "M4", "MS4", "MN4",
    "2N2", "MU2", "NU2", "L2", "T2", "J1", "MM", "MSF", "MF", "M6", "S4", "M3",
]
NAME_TO_ID = {name: i for i, name in enumerate(BASIS_NAMES)}

ENERGY_FLOOR_PCT = 0.02
ENERGY_FLOOR_MIN_KN = 0.005
R2_FLOOR = 0.8
MAX_BYTES = 40 * 1024 * 1024


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    with open(path, "rb") as fh:
        return sha256_bytes(fh.read())


def _axis_floor(constituents):
    """§3 floor (amended from §10's sizing estimate, see module docstring):
    max(2% of THIS axis's own max amplitude across this element's fitted
    constituents, 0.005 kn)."""
    if not constituents:
        return ENERGY_FLOOR_MIN_KN
    axis_max = max(c["amplitude"] for c in constituents)
    return max(ENERGY_FLOOR_PCT * axis_max, ENERGY_FLOOR_MIN_KN)


def prune_axis(constituents):
    """Filter one axis's fitted constituents by its own energy floor.
    Unknown constituent names are a hard error, never a silent drop -- a
    name outside the pinned 23-name basis means the id table has drifted
    from the fitter, not "ship without it"."""
    for c in constituents:
        if c["name"] not in NAME_TO_ID:
            raise ValueError(
                f"unknown constituent {c['name']!r} -- not in the "
                f"{len(BASIS_NAMES)}-name shipping basis {BASIS_NAMES}")
    floor = _axis_floor(constituents)
    return [c for c in constituents if c["amplitude"] >= floor]


def pack_element(verts, constituents_u, constituents_v):
    """verts: [[lon, lat]] x3. Returns (chunk_bytes, kept_u, kept_v)."""
    assert len(verts) == 3, f"expected 3 verts, got {len(verts)}"
    kept_u = prune_axis(constituents_u)
    kept_v = prune_axis(constituents_v)
    buf = bytearray()
    buf += struct.pack("<B", 3)
    for lon, lat in verts:
        buf += struct.pack("<ff", lon, lat)
    for kept in (kept_u, kept_v):
        buf += struct.pack("<B", len(kept))
        for c in kept:
            buf += struct.pack("<Bee", NAME_TO_ID[c["name"]], c["amplitude"], c["phase"])
    return bytes(buf), kept_u, kept_v


def pack_elements(elements_data):
    """elements_data: [(i, verts, constituents_u, constituents_v), ...] in
    ship order. Returns (bin_bytes, offsets) -- offsets is a prefix-sum
    array of length len(elements_data)+1 (offsets[k]..offsets[k+1] is
    element k's byte range; offsets[-1] is the total bin size)."""
    buf = bytearray()
    offsets = [0]
    for i, verts, cu, cv in elements_data:
        try:
            chunk, _, _ = pack_element(verts, cu, cv)
        except ValueError as e:
            raise ValueError(f"element {i}: {e}") from e
        buf += chunk
        offsets.append(len(buf))
    return bytes(buf), offsets


def _corpus_window(corpus_dir):
    files = sorted(os.path.basename(f) for f in glob.glob(os.path.join(corpus_dir, "*.npz")))
    if not files:
        raise ValueError(f"no corpus files in {corpus_dir} -- can't derive corpus_window")
    def iso_date(fname):
        d = fname[:8]
        return f"{d[0:4]}-{d[4:6]}-{d[6:8]}"
    return {"start": iso_date(files[0]), "end": iso_date(files[-1])}


def build_header(*, mesh, mesh_path, stations_path, corpus_dir, survivors,
                  bin_bytes, offsets, generated):
    return {
        "format_version": 1,
        "region": "salish",
        "bbox": mesh["bbox"],
        "corpus_window": _corpus_window(corpus_dir),
        "mesh_source": {"url": mesh.get("file"), "sha256": sha256_file(mesh_path)},
        "D_m": survivors["D_m"],
        "floors": {
            "r2_min": R2_FLOOR,
            "energy_pct": ENERGY_FLOOR_PCT,
            "energy_min_kn": ENERGY_FLOOR_MIN_KN,
            "note": ("per-axis independently at pack time -- differs from "
                     "composite-design.md §10's sizing estimate, which "
                     "kept a constituent for both axes if either cleared"),
        },
        "station_set": {"path": stations_path, "sha256": sha256_file(stations_path)},
        "generated": generated,
        "element_count": len(offsets) - 1,
        "constituents": {str(i): name for i, name in enumerate(BASIS_NAMES)},
        "constituent_basis_source": "spikes/sscofs-field/prune_proof.py:34-35",
        "bin_sha256": sha256_bytes(bin_bytes),
        "offsets": offsets,
    }


def pack(survivors_path, mesh_path, stations_path, corpus_dir,
         generated=None, max_bytes=MAX_BYTES):
    """Reads the three JSON inputs, prunes + packs, hard-asserts the size
    budget. `generated` defaults to now (UTC) -- the only datetime.now()
    call site in this module, and injectable so tests never race the clock."""
    with open(survivors_path) as fh:
        survivors = json.load(fh)
    with open(mesh_path) as fh:
        mesh = json.load(fh)
    verts_by_i = {e["i"]: e["verts"] for e in mesh["elements"]}

    elements_data = []
    for el in survivors["elements"]:
        i = el["i"]
        if i not in verts_by_i:
            raise ValueError(f"survivor element {i} not found in {mesh_path}")
        r2_u, r2_v = el["r2_u"], el["r2_v"]
        # Trust-boundary re-check: survivors.json is supposed to already be
        # R^2-filtered upstream (Task 4's §4a + shipping-fit floor), but
        # pack.py doesn't take that on faith -- a regression there should
        # fail loudly here, not ship a weakly-tidal element silently.
        if r2_u < R2_FLOOR or r2_v < R2_FLOOR:
            raise ValueError(
                f"element {i}: r2_u={r2_u} r2_v={r2_v} below floor {R2_FLOOR} "
                "-- survivors.json should already be filtered upstream")
        elements_data.append((i, verts_by_i[i], el["constituents_u"], el["constituents_v"]))

    bin_bytes, offsets = pack_elements(elements_data)
    assert len(bin_bytes) <= max_bytes, (
        f"bundle {len(bin_bytes)} bytes exceeds {max_bytes} byte budget "
        f"({len(bin_bytes) / 1e6:.2f} MB vs {max_bytes / 1e6:.2f} MB) -- "
        "shrink the survivor set or basis before shipping")

    generated = generated or datetime.now(timezone.utc).isoformat()
    header = build_header(mesh=mesh, mesh_path=mesh_path, stations_path=stations_path,
                           corpus_dir=corpus_dir, survivors=survivors, bin_bytes=bin_bytes,
                           offsets=offsets, generated=generated)
    return bin_bytes, header


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--survivors", default="data/survivors.json")
    ap.add_argument("--mesh", default="data/mesh.json")
    ap.add_argument("--stations", default="data/stations.json")
    ap.add_argument("--corpus-dir", default="data/corpus")
    ap.add_argument("--out-bin", default="../../Slackwater/Resources/fill-salish.bin")
    ap.add_argument("--out-json", default="../../Slackwater/Resources/fill-salish.json")
    args = ap.parse_args()

    bin_bytes, header = pack(args.survivors, args.mesh, args.stations, args.corpus_dir)

    out_dir = os.path.dirname(args.out_bin)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out_bin, "wb") as fh:
        fh.write(bin_bytes)
    with open(args.out_json, "w") as fh:
        json.dump(header, fh, indent=1)
    mb = len(bin_bytes) / 1e6
    print(f"packed {header['element_count']} elements, {len(bin_bytes)} bytes "
          f"({mb:.2f} MB) -> {args.out_bin} + {args.out_json}")


if __name__ == "__main__":
    main()
