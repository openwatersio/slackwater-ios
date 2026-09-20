#!/usr/bin/env -S uv run --script --with numpy
"""Speed-only certification geometry (spec §4a): grade truth stations from
results/*.json, then certify/mask/leave-uncertified every box element by
nearest-scoreable-station distance. Fill-channel gate only — no timing here.

Outputs: certified/certified.json, certified/certified.geojson, certified/CERTIFY.md
"""
import json, os
import numpy as np

D_M = 3000  # spec §4a default
SENSITIVITY_D_M = (2000, 3000, 5000)
M_PER_DEG_LAT = 111320.0

# gabriola-passage / tillicum-bridge never got a mesh element within 600 m
# (make_samples.py, see report.py) — absent from samples/index.json, so they
# never enter station_verdicts() and grade nothing, per spec.


def station_verdicts(index, results_dir="results"):
    """Per station: drop results/*.json rows with the -1 sentinel
    (speedMedianKn < 0, fit-validation's "no scoreable extremum"); UNSCOREABLE
    if none survive, else PASS iff the best (min) surviving speedMedianKn <= 0.5."""
    by_slug = {}
    for row in index:
        by_slug.setdefault(row["slug"], []).append(row)

    out = []
    for slug, rows in sorted(by_slug.items()):
        speeds = []
        for row in rows:
            path = f"{results_dir}/{slug}-e{row['elem']}.json"
            if not os.path.exists(path):
                continue
            sm = json.load(open(path))["speedMedianKn"]
            if sm >= 0:
                speeds.append(sm)
        if not speeds:
            out.append({"slug": slug, "verdict": "UNSCOREABLE", "speed_med": None})
        else:
            best = min(speeds)
            out.append({"slug": slug, "verdict": "PASS" if best <= 0.5 else "FAIL", "speed_med": best})
    return out


def grade_elements(elements, stations, D_m):
    """Nearest scoreable (PASS/FAIL) station by flat-earth metres (x111320,
    cos(lat) on lon, each station's own lat for the cos term). PASS within D_m
    -> "yes", FAIL within D_m -> "masked", else -> "none". UNSCOREABLE stations
    grade nothing: excluded from the nearest-station search entirely."""
    scoreable = [s for s in stations if s["verdict"] in ("PASS", "FAIL")]
    if not scoreable:
        return ["none"] * len(elements)

    elem_lon = np.array([e["lon"] for e in elements])
    elem_lat = np.array([e["lat"] for e in elements])
    st_lon = np.array([s["lon"] for s in scoreable])
    st_lat = np.array([s["lat"] for s in scoreable])
    cos_lat = np.cos(np.radians(st_lat))

    dx = (elem_lon[:, None] - st_lon[None, :]) * M_PER_DEG_LAT * cos_lat[None, :]
    dy = (elem_lat[:, None] - st_lat[None, :]) * M_PER_DEG_LAT
    dist = np.hypot(dx, dy)  # [n_elements, n_scoreable]

    nearest = np.argmin(dist, axis=1)
    nearest_dist = dist[np.arange(len(elements)), nearest]

    statuses = []
    for i in range(len(elements)):
        if nearest_dist[i] > D_m:
            statuses.append("none")
        elif scoreable[nearest[i]]["verdict"] == "PASS":
            statuses.append("yes")
        else:
            statuses.append("masked")
    return statuses


def main():
    elements = json.load(open("mesh/elements.json"))["elements"]
    index = json.load(open("samples/index.json"))
    truth_by_slug = {s["slug"]: s for s in json.load(open("truth/stations.json"))}

    stations = station_verdicts(index)
    for s in stations:
        t = truth_by_slug[s["slug"]]
        s["lat"], s["lon"] = t["lat"], t["lon"]

    sensitivity = {str(D): sum(1 for st in grade_elements(elements, stations, D) if st == "yes")
                   for D in SENSITIVITY_D_M}

    statuses = grade_elements(elements, stations, D_M)
    certified_ids = [e["i"] for e, st in zip(elements, statuses) if st == "yes"]

    os.makedirs("certified", exist_ok=True)

    out = {
        "D_m": D_M,
        "elements": certified_ids,
        "stations": [{"slug": s["slug"], "verdict": s["verdict"], "speed_med": s["speed_med"]} for s in stations],
        "sensitivity": sensitivity,
    }
    json.dump(out, open("certified/certified.json", "w"), indent=1)

    geo = {
        "type": "FeatureCollection",
        "features": [
            {"type": "Feature", "properties": {"i": e["i"], "certified": st},
             "geometry": {"type": "Point", "coordinates": [e["lon"], e["lat"]]}}
            for e, st in zip(elements, statuses)
        ],
    }
    json.dump(geo, open("certified/certified.geojson", "w"))

    n = len(elements)
    counts = {k: statuses.count(k) for k in ("yes", "masked", "none")}
    n_pass = sum(1 for s in stations if s["verdict"] == "PASS")
    n_fail = sum(1 for s in stations if s["verdict"] == "FAIL")
    n_unsc = sum(1 for s in stations if s["verdict"] == "UNSCOREABLE")

    with open("certified/CERTIFY.md", "w") as out_md:
        out_md.write("# Certification geometry (spec §4a)\n\n")
        out_md.write(f"## Station verdicts ({len(stations)} stations scored, {n_pass + n_fail} scoreable)\n\n")
        out_md.write(f"- PASS: {n_pass}\n- FAIL: {n_fail}\n- UNSCOREABLE: {n_unsc}\n\n")
        out_md.write("| station | verdict | speed_med (kn) |\n|---|---|---|\n")
        for s in stations:
            sm = f"{s['speed_med']:.2f}" if s["speed_med"] is not None else "-"
            out_md.write(f"| {s['slug']} | {s['verdict']} | {sm} |\n")

        out_md.write(f"\n## Element geometry (D = {D_M} m, {n} box elements)\n\n")
        out_md.write("| status | count | % |\n|---|---|---|\n")
        for k in ("yes", "masked", "none"):
            out_md.write(f"| {k} | {counts[k]} | {counts[k] / n * 100:.1f}% |\n")

        out_md.write("\n## Sensitivity (certified count by D)\n\n")
        out_md.write("| D (m) | certified elements | % |\n|---|---|---|\n")
        for D in SENSITIVITY_D_M:
            c = sensitivity[str(D)]
            out_md.write(f"| {D} | {c} | {c / n * 100:.1f}% |\n")
    print(open("certified/CERTIFY.md").read())


if __name__ == "__main__":
    main()
