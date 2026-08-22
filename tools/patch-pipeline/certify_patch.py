#!/usr/bin/env -S uv run --script --with numpy,requests
"""Slackwater patch-pipeline — method certification (grown-patches spec §6a).

For every check station of every pass with one: samples = the anchor's own
CO-OPS prediction series x scale(check section), signed; events = the check
station's published MAX_SLACK truth. run_certify.sh then grades each pair
with tools/FitValidation — the M47 bars, one implementation, never a fork.

Anchor series via CO-OPS `currents_predictions` interval=6 (Velocity_Major,
signed kn on the anchor's flood axis), fetched in ~30-day chunks over the
same 190-day style window the fill corpus used. Event fetch idiom is
make_matrix.py's noaa_events, reused by import.
"""
import json, math, os, sys, datetime as dt

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "fill-pipeline"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "spikes", "sscofs-field"))
from make_samples import to_sample          # one epoch-ms sample rule in the repo
from make_matrix import noaa_events, CP     # one NOAA event idiom
import requests

M_PER_DEG_LAT = 111320.0
FIT_DAYS = 190
VAL_OFFSET_DAYS, VAL_LEN_DAYS = 28, 7       # mirror make_matrix's held-out window


def nearest_section(pass_doc, lat, lon):
    """Index of the kept section nearest (lat, lon); hard error if none is close."""
    lo, hi = pass_doc["kept_range"]
    best, best_d = None, float("inf")
    for i in range(lo, hi + 1):
        c = pass_doc["sections"][i]["center"]
        d = math.hypot((c[0] - lon) * M_PER_DEG_LAT * math.cos(math.radians(lat)),
                       (c[1] - lat) * M_PER_DEG_LAT)
        if d < best_d:
            best, best_d = i, d
    if best is None or best_d > pass_doc.get("section_spacing_m", 150) * 2:
        raise SystemExit(f"check station {lat},{lon} has no section within 2 spacings of kept_range")
    return best


def nearest_scale(pass_doc, lat, lon):
    return pass_doc["scales"][nearest_section(pass_doc, lat, lon)]


def reciprocal_spec(pass_doc, inputs):
    """The reciprocal in-bounds check (spec 6a, amended): grade the *anchor*
    station from one of the check stations, same geometry, scales renormalized
    so the reciprocal anchor's section is 1.0. scales[i] = A_anchor/A_i, so
    A_recip/A_i = scales[i]/scales[recip] — one division, no re-derivation.
    Returns None for a pass without a `reciprocal_check` input."""
    rc = inputs.get("reciprocal_check")
    if not rc:
        return None
    ra = next(c for c in inputs["check_stations"] if c["station_id"] == rc["anchor_station_id"])
    i_recip = nearest_section(pass_doc, ra["lat"], ra["lon"])
    t = rc["target"]
    i_target = nearest_section(pass_doc, t["lat"], t["lon"])
    return {"label": f"{pass_doc['slug']}-recip-{t['station_id']}",
            "anchor_id": rc["anchor_station_id"], "target": t,
            "scale": round(pass_doc["scales"][i_target] / pass_doc["scales"][i_recip], 4)}


def scale_samples(samples, scale):
    return [{"t": s["t"], "v": s["v"] * scale} for s in samples]


def anchor_series(station_id, start, end):
    """Signed Velocity_Major kn, 6-min, chunked ~30 days (API range limit)."""
    out = []
    t0 = start
    while t0 < end:
        t1 = min(t0 + dt.timedelta(days=30), end)
        r = requests.get(CP, params={"station": station_id, "product": "currents_predictions",
                                     "begin_date": f"{t0:%Y%m%d}", "end_date": f"{t1:%Y%m%d}",
                                     "interval": "6", "units": "english",
                                     "time_zone": "gmt", "format": "json"}, timeout=120).json()
        for e in r["current_predictions"]["cp"]:
            ts = dt.datetime.strptime(e["Time"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
            out.append(to_sample(ts.timestamp(), float(e["Velocity_Major"])))
        t0 = t1
    return out


def main():
    end = dt.datetime.now(dt.timezone.utc).replace(minute=0, second=0, microsecond=0)
    start = end - dt.timedelta(days=FIT_DAYS)
    val = (end + dt.timedelta(days=VAL_OFFSET_DAYS), end + dt.timedelta(days=VAL_OFFSET_DAYS + VAL_LEN_DAYS))
    os.makedirs("data/certify/samples", exist_ok=True)
    os.makedirs("data/certify/events", exist_ok=True)
    index = []
    for f in sorted(os.listdir("passes")):
        if not f.endswith(".json"):
            continue
        pass_doc = json.load(open(f"passes/{f}"))
        inputs = json.load(open(f"inputs/{pass_doc['slug']}.json"))
        if not inputs.get("check_stations"):
            continue
        anchor = pass_doc["anchor"]
        base = anchor_series(anchor["station_id"], start, end)
        for ck in inputs["check_stations"]:
            label = f"{pass_doc['slug']}-{ck['station_id']}"
            sp = f"data/certify/samples/{label}.json"
            ep = f"data/certify/events/{label}.json"
            if not (os.path.exists(sp) and os.path.exists(ep)):   # resumable
                s = nearest_scale(pass_doc, ck["lat"], ck["lon"])
                json.dump(scale_samples(base, s), open(sp, "w"))
                json.dump(noaa_events({"id": ck["station_id"]}, *val), open(ep, "w"))
            index.append({"slug": label, "samples": sp, "events": ep,
                          "flood": ck["flood_deg"], "ebb": ck["ebb_deg"]})
            print(label)
        rc = reciprocal_spec(pass_doc, inputs)
        if rc:
            t = rc["target"]
            sp = f"data/certify/samples/{rc['label']}.json"
            ep = f"data/certify/events/{rc['label']}.json"
            if not (os.path.exists(sp) and os.path.exists(ep)):   # resumable
                json.dump(scale_samples(anchor_series(rc["anchor_id"], start, end), rc["scale"]),
                          open(sp, "w"))
                json.dump(noaa_events({"id": t["station_id"]}, *val), open(ep, "w"))
            index.append({"slug": rc["label"], "samples": sp, "events": ep,
                          "flood": t["flood_deg"], "ebb": t["ebb_deg"]})
            print(f"{rc['label']} (scale {rc['scale']} from {rc['anchor_id']})")
    json.dump(index, open("data/certify/index.json", "w"), indent=1)


if __name__ == "__main__":
    main()
