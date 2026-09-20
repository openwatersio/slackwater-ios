#!/usr/bin/env -S uv run --script --with h5py,fsspec,aiohttp,numpy
"""Fetch 60 days of hourly surface u/v for the box elements. Resumable: skips existing day files."""
import json, os, sys, datetime as dt, concurrent.futures as cf
import numpy as np, h5py, fsspec

BUCKET = "https://noaa-nos-ofs-pds.s3.amazonaws.com/sscofs/netcdf"
CYCLES = (3, 9, 15, 21)          # ×n001..n006 → 24 hourly steps/day
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 60

def hour_urls(day):
    # ponytail: shard name YYYYMMDD is a fetch-batch label, not a time contract. Files contain
    # day−1 22:00Z .. day+0 21:00Z (offset range −2..+21 hours). Consumers must key on stored
    # t array (epoch seconds), never the filename. Contiguous, no dupes; sorted by t.
    for c in CYCLES:
        for n in range(1, 7):
            yield (f"{BUCKET}/{day:%Y/%m/%d}/sscofs.t{c:02d}z.{day:%Y%m%d}.fields.n{n:03d}.nc",
                   dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc)
                   + dt.timedelta(hours=c - 6 + n))

def fetch_hour(url, idx):
    try:
        with h5py.File(fsspec.open(url, "rb").open(), "r") as f:
            return f["u"][0, 0, :][idx], f["v"][0, 0, :][idx]   # surface = siglay 0
    except Exception as e:
        print(f"  miss {url.rsplit('/',1)[1]}: {type(e).__name__}")
        return None

def main():
    els = json.load(open("mesh/elements.json"))["elements"]
    idx = np.array([e["i"] for e in els])
    os.makedirs("corpus", exist_ok=True)
    today = dt.datetime.now(dt.timezone.utc).date()
    for back in range(DAYS, 0, -1):
        day = today - dt.timedelta(days=back)
        out = f"corpus/{day:%Y%m%d}.npz"
        if os.path.exists(out):
            continue
        pairs = list(hour_urls(dt.datetime(day.year, day.month, day.day)))
        t = np.array([ts.timestamp() for _, ts in pairs])
        u = np.full((24, len(idx)), np.nan, np.float32); v = u.copy()
        with cf.ThreadPoolExecutor(max_workers=5) as ex:
            futs = {ex.submit(fetch_hour, url, idx): k for k, (url, _) in enumerate(pairs)}
            for fut in cf.as_completed(futs):
                r = fut.result()
                if r is not None:
                    u[futs[fut]], v[futs[fut]] = r
        ok = int(np.isfinite(u[:, 0]).sum())
        if ok >= 20:
            np.savez_compressed(out, t=t, u=u, v=v)
        print(f"{day} {ok}/24 hours {'saved' if ok >= 20 else 'SKIPPED'}")

if __name__ == "__main__":
    main()
