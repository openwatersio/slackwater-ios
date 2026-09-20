#!/usr/bin/env -S uv run --script --with h5py,fsspec,aiohttp,numpy,requests
"""Subset the SSCOFS mesh to the Salish render region.

Uses the box-validation connectivity checks from tools/sscofs-validation/mesh_subset.py.
Writes data/mesh.json; the bbox and output contract are documented in README.md."""
import json, os, sys, datetime as dt
import numpy as np, h5py, fsspec

BBOX = (-125.5, 47.0, -122.0, 50.6)  # lonW, latS, lonE, latN (spec §1 region)
BUCKET = "https://noaa-nos-ofs-pds.s3.amazonaws.com/sscofs/netcdf"

# Nearest-element sanity checks (spec's reference passes), < 600 m.
REFS = {"seymour": (50.1333, -125.3500), "tacoma": (47.2690, -122.5510)}


def latest_url(days_back=1):
    d = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days_back)
    return f"{BUCKET}/{d:%Y/%m/%d}/sscofs.t03z.{d:%Y%m%d}.fields.n001.nc"


def _norm_lon(lon):
    return np.where(lon > 180, lon - 360, lon)


def _vertex_ids(nv, nele):
    """nv has one axis of length 3 (per-element vertex triplet) and one of
    length nele; don't assume which -- detect it from the actual shape."""
    if nv.shape[0] == 3 and nv.shape[1] == nele:
        return nv
    if nv.shape[1] == 3 and nv.shape[0] == nele:
        return nv.T
    raise AssertionError(f"nv shape {nv.shape} matches neither axis to nele={nele}")


def _choose_base(nv3, lon, lat, lonc, latc, sample_idx):
    """FVCOM's nv is documented 1-based, but don't take that on faith -- try
    both bases and keep whichever makes the vertex mean match the file's own
    centroid (lonc/latc) within 100 m. Hard-asserts if neither does."""
    chosen = None
    for base in (1, 0):
        node_ids = nv3[:, sample_idx] - base
        if node_ids.min() < 0 or node_ids.max() >= len(lon):
            print(f"  base={base}: node id out of range, skipped")
            continue
        vlon = lon[node_ids].mean(axis=0)
        vlat = lat[node_ids].mean(axis=0)
        d = np.hypot((vlat - latc[sample_idx]) * 111320,
                     (vlon - lonc[sample_idx]) * 111320 * np.cos(np.radians(latc[sample_idx])))
        dmax = float(d.max())
        print(f"  base={base}: max centroid-vs-vertex-mean drift over {len(sample_idx)}-element sample = {dmax:.1f} m")
        if dmax < 100 and chosen is None:
            chosen = base
    assert chosen is not None, "neither 0-based nor 1-based nv indexing matched centroids within 100 m"
    return chosen


def main():
    url = sys.argv[1] if len(sys.argv) > 1 else latest_url()
    with h5py.File(fsspec.open(url, "rb").open(), "r") as f:
        lonc, latc = _norm_lon(f["lonc"][:]), f["latc"][:]
        lon, lat = _norm_lon(f["lon"][:]), f["lat"][:]
        nv = f["nv"][:]

    nele = len(lonc)
    nv3 = _vertex_ids(nv, nele)

    w, s, e, n = BBOX
    idx = np.where((lonc >= w) & (lonc <= e) & (latc >= s) & (latc <= n))[0]
    print(f"{len(idx)} elements in region (full mesh {nele})")

    rng = np.random.default_rng(0)
    sample = rng.choice(idx, size=min(1000, len(idx)), replace=False)
    base = _choose_base(nv3, lon, lat, lonc, latc, sample)
    print(f"  nv is {base}-based; centroid check passed")

    node_ids = nv3[:, idx] - base            # (3, len(idx))
    vlon = lon[node_ids]                     # (3, len(idx))
    vlat = lat[node_ids]
    verts = np.transpose(np.stack([vlon, vlat], axis=-1), (1, 0, 2)).tolist()  # (len(idx), 3, 2)

    elements = [
        {"i": i, "lon": lo, "lat": la, "verts": v}
        for i, lo, la, v in zip(idx.tolist(), lonc[idx].tolist(), latc[idx].tolist(), verts)
    ]
    out = {"file": url, "bbox": list(BBOX), "elements": elements}
    os.makedirs("data", exist_ok=True)
    with open("data/mesh.json", "w") as fh:
        json.dump(out, fh)

    for name, (la, lo) in REFS.items():
        dmin = float(np.min(np.hypot((latc[idx] - la) * 111320,
                                      (lonc[idx] - lo) * 111320 * np.cos(np.radians(la)))))
        assert dmin < 600, f"{name}: nearest element {dmin:.0f} m"
        print(f"  {name}: nearest element {dmin:.0f} m")


if __name__ == "__main__":
    main()
