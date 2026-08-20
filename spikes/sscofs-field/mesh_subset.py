#!/usr/bin/env -S uv run --script --with h5py,fsspec,aiohttp,numpy,requests
"""Subset SSCOFS element centroids to the spike box. Downloads one fields file header remotely (ranged reads) — no full download."""
import json, sys, datetime as dt
import numpy as np, h5py, fsspec

BOX = (-123.95, 48.30, -122.55, 49.25)  # lonW, latS, lonE, latN
BUCKET = "https://noaa-nos-ofs-pds.s3.amazonaws.com/sscofs/netcdf"

def latest_url(days_back=1):
    d = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days_back)
    return f"{BUCKET}/{d:%Y/%m/%d}/sscofs.t03z.{d:%Y%m%d}.fields.n001.nc"

def main():
    url = sys.argv[1] if len(sys.argv) > 1 else latest_url()
    with h5py.File(fsspec.open(url, "rb").open(), "r") as f:
        lonc, latc = f["lonc"][:], f["latc"][:]
    lonc = np.where(lonc > 180, lonc - 360, lonc)
    w, s, e, n = BOX
    idx = np.where((lonc >= w) & (lonc <= e) & (latc >= s) & (latc <= n))[0]
    out = {"file": url, "box": list(BOX),
           "elements": [{"i": int(i), "lon": float(lonc[i]), "lat": float(latc[i])} for i in idx]}
    with open("mesh/elements.json", "w") as fh:
        json.dump(out, fh)
    print(f"{len(idx)} elements in box (full mesh {len(lonc)})")
    # Self-check: the four reference passes must each have an element within 600 m.
    refs = {"dodd": (49.1367, -123.8183), "active": (48.8667, -123.3000),
            "boundary": (48.7621, -123.0520), "sanjuan": (48.4600, -122.9500)}
    for name, (la, lo) in refs.items():
        dmin = float(np.min(np.hypot((latc[idx] - la) * 111320,
                                     (lonc[idx] - lo) * 111320 * np.cos(np.radians(la)))))
        assert dmin < 600, f"{name}: nearest element {dmin:.0f} m"
        print(f"  {name}: nearest element {dmin:.0f} m")

if __name__ == "__main__":
    import os; os.makedirs("mesh", exist_ok=True); main()
