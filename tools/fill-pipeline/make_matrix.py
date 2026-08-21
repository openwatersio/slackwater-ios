#!/usr/bin/env -S uv run --script --with numpy,requests
"""Project region-mesh element u/v onto each truth station's flood axis;
export fitTides samples + held-out truth events.

Forked from spikes/sscofs-field/make_samples.py (state provenance: that spike
ran to completion against real SSCOFS data, see spikes/sscofs-field/README.md)
per fill-phase-b-design.md §1 / task-2-brief.md: paths point at
tools/fill-pipeline/data/ (region mesh + 190-day corpus + region stations)
instead of the spike's box-scoped dirs, and the index/events layout is
data/index.json + data/samples/ + data/events/ per the task interface.
`to_sample`/`project_signed_kn` are imported from the spike rather than
reimplemented, so there is exactly one epoch-ms / projection rule in the repo.
Legitimate fork, not an import for the rest -- the §4a-grading no-fork rule
(spikes/sscofs-field/certify.py) applies only to certification.
"""
import glob, json, os, sys, datetime as dt
import numpy as np, requests

# One epoch-ms sample rule and one flood-axis-projection rule, period --
# import rather than reimplement (chs-glue.js:4 contract: {t: epoch-ms, v: signed knots}).
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "spikes", "sscofs-field"))
from make_samples import to_sample, project_signed_kn  # noqa: E402

IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
CP = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"


def load_corpus():
    files = sorted(glob.glob("data/corpus/*.npz"))
    t = np.concatenate([np.load(f)["t"] for f in files])
    u = np.concatenate([np.load(f)["u"] for f in files])
    v = np.concatenate([np.load(f)["v"] for f in files])
    order = np.argsort(t)
    return t[order], u[order], v[order]


def elements_near(els, lat, lon, radius_m=600):
    # k = position in `els` (== `data/mesh.json`'s elements list, ascending
    # full-mesh index order) -- that position is also the column index into
    # the corpus u/v arrays, because fetch_region.py fetched columns in the
    # same mesh.json list order. e["i"] is the full-mesh element index, used
    # only for labeling (samples/<slug>-e<i>.json), never for column lookup.
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


def main():
    els = json.load(open("data/mesh.json"))["elements"]
    stations = json.load(open("data/stations.json"))
    t, u, v = load_corpus()
    fit_end = dt.datetime.fromtimestamp(t[-1], dt.timezone.utc)
    val = (fit_end + dt.timedelta(days=28), fit_end + dt.timedelta(days=35))
    os.makedirs("data/samples", exist_ok=True)
    os.makedirs("data/events", exist_ok=True)
    index = []
    for st in stations:
        try:
            near = elements_near(els, st["lat"], st["lon"])
            if not near:
                print(f"{st['slug']}: NO ELEMENT within 600 m — record as coverage gap")
                continue

            ev_path = f"data/events/{st['slug']}-events.json"

            # resumability: skip if already fetched + sampled
            sample_files = [f"data/samples/{st['slug']}-e{i}.json" for _, i, _ in near]
            if os.path.exists(ev_path) and all(os.path.exists(sp) for sp in sample_files):
                # rebuild index rows from disk
                events = json.load(open(ev_path))
                for k, i, d in near:
                    sp = f"data/samples/{st['slug']}-e{i}.json"
                    index.append({"slug": st["slug"], "elem": int(i), "samples": sp, "events": ev_path,
                                  "flood": st["flood"], "ebb": st["ebb"], "dist_m": round(d)})
                print(f"{st['slug']}: {len(near)} elements, {len(events)} truth events (resumed)")
                json.dump(index, open("data/index.json", "w"), indent=1)
                continue

            events = chs_events(st, *val) if st["source"] == "chs" else noaa_events(st, *val)
            json.dump(events, open(ev_path, "w"))
            for k, i, d in near:
                signed = project_signed_kn(u[:, k], v[:, k], st["flood"])
                good = np.isfinite(signed)
                sp = f"data/samples/{st['slug']}-e{i}.json"
                json.dump([to_sample(tt, vv) for tt, vv in zip(t[good], signed[good])],
                          open(sp, "w"))
                index.append({"slug": st["slug"], "elem": int(i), "samples": sp, "events": ev_path,
                              "flood": st["flood"], "ebb": st["ebb"], "dist_m": round(d)})
            print(f"{st['slug']}: {len(near)} elements, {len(events)} truth events")

            # incremental write: preserve completed stations on disk
            json.dump(index, open("data/index.json", "w"), indent=1)

        except Exception as e:
            print(f"{st['slug']}: FAILED {type(e).__name__}: {e}")
            continue


if __name__ == "__main__":
    main()
