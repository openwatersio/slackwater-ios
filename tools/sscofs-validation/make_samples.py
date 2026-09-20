#!/usr/bin/env -S uv run --script --with numpy,requests
"""Project box-element u/v onto each truth station's flood axis; export fitTides samples + held-out truth events."""
import glob, json, os, datetime as dt
import numpy as np, requests

MS_TO_KN = 1.94384
IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
CP = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

def project_signed_kn(u, v, flood_deg):
    """signed = speed·cos(dir − flood): the harness/chs-constituents projection (main.swift:189)."""
    speed = np.hypot(u, v) * MS_TO_KN
    direction = np.degrees(np.arctan2(u, v)) % 360.0
    return speed * np.cos(np.radians(direction - flood_deg))

def load_corpus():
    files = sorted(glob.glob("corpus/*.npz"))
    t = np.concatenate([np.load(f)["t"] for f in files])
    u = np.concatenate([np.load(f)["u"] for f in files])
    v = np.concatenate([np.load(f)["v"] for f in files])
    order = np.argsort(t)
    return t[order], u[order], v[order]

def elements_near(els, lat, lon, radius_m=600):
    out = []
    for k, e in enumerate(els):
        d = np.hypot((e["lat"] - lat) * 111320, (e["lon"] - lon) * 111320 * np.cos(np.radians(lat)))
        if d <= radius_m:
            out.append((k, e["i"], d))
    return out

def chs_events(st, start, end):
    q = f"{IWLS}/stations/{st['iwlsId']}/data?time-series-code=wcp1-events&from={start:%Y-%m-%dT%H:%M:%SZ}&to={end:%Y-%m-%dT%H:%M:%SZ}"
    return requests.get(q, timeout=60).json()  # already [{eventDate, qualifier, value}]

def noaa_events(st, start, end):
    # ponytail: date-truncated by API limitation; window skews wider (conservative) — intentional
    r = requests.get(CP, params={"station": st["id"], "product": "currents_predictions",
                                 "begin_date": f"{start:%Y%m%d}", "end_date": f"{end:%Y%m%d}",
                                 "interval": "MAX_SLACK", "units": "english",
                                 "time_zone": "gmt", "format": "json"}, timeout=60).json()
    out = []
    for e in r["current_predictions"]["cp"]:
        vel = float(e["Velocity_Major"])
        kind = ("SLACK" if e["Type"] == "slack" else
                "EXTREMA_FLOOD" if vel > 0 else "EXTREMA_EBB")
        out.append({"eventDate": e["Time"].replace(" ", "T") + ":00Z",
                    "qualifier": kind, "value": abs(vel)})
    return out

def to_sample(tt, vv):
    """Export fitTides sample: epoch-ms per chs-glue.js:4 contract ({t: epoch-ms, v: signed knots})."""
    return {"t": int(tt * 1000), "v": float(vv)}

def main():
    els = json.load(open("mesh/elements.json"))["elements"]
    stations = json.load(open("truth/stations.json"))
    t, u, v = load_corpus()
    fit_end = dt.datetime.fromtimestamp(t[-1], dt.timezone.utc)
    val = (fit_end + dt.timedelta(days=28), fit_end + dt.timedelta(days=35))
    os.makedirs("samples", exist_ok=True)
    index = []
    for st in stations:
        try:
            near = elements_near(els, st["lat"], st["lon"])
            if not near:
                print(f"{st['slug']}: NO ELEMENT within 600 m — record as coverage gap")
                continue

            ev_path = f"truth/{st['slug']}-events.json"

            # resumability: skip if already fetched + sampled
            sample_files = [f"samples/{st['slug']}-e{i}.json" for _, i, _ in near]
            if os.path.exists(ev_path) and all(os.path.exists(sp) for sp in sample_files):
                # rebuild index rows from disk
                events = json.load(open(ev_path))
                for k, i, d in near:
                    sp = f"samples/{st['slug']}-e{i}.json"
                    index.append({"slug": st["slug"], "elem": int(i), "samples": sp, "events": ev_path,
                                  "flood": st["flood"], "ebb": st["ebb"], "dist_m": round(d)})
                print(f"{st['slug']}: {len(near)} elements, {len(events)} truth events (resumed)")
                json.dump(index, open("samples/index.json", "w"), indent=1)
                continue

            events = chs_events(st, *val) if st["source"] == "chs" else noaa_events(st, *val)
            json.dump(events, open(ev_path, "w"))
            for k, i, d in near:
                signed = project_signed_kn(u[:, k], v[:, k], st["flood"])
                good = np.isfinite(signed)
                sp = f"samples/{st['slug']}-e{i}.json"
                json.dump([to_sample(tt, vv) for tt, vv in zip(t[good], signed[good])],
                          open(sp, "w"))
                index.append({"slug": st["slug"], "elem": int(i), "samples": sp, "events": ev_path,
                              "flood": st["flood"], "ebb": st["ebb"], "dist_m": round(d)})
            print(f"{st['slug']}: {len(near)} elements, {len(events)} truth events")

            # incremental write: preserve completed stations on disk
            json.dump(index, open("samples/index.json", "w"), indent=1)

        except Exception as e:
            print(f"{st['slug']}: FAILED {type(e).__name__}: {e}")
            continue

if __name__ == "__main__":
    main()
