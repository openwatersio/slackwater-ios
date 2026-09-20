#!/usr/bin/env -S uv run --script --with requests
"""Discover CHS and NOAA truth stations throughout the Salish render region.

Uses the discovery method in tools/sscofs-validation/truth_stations.py with the
region bbox. Writes data/stations.json; see README.md for scoring and provenance."""
import json, os, requests, time

BOX = (-125.5, 47.0, -122.0, 50.6)  # lonW, latS, lonE, latN (spec §1 region)
IWLS = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
MD = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi"
CP = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

def inbox(lat, lon):
    w, s, e, n = BOX
    return s <= lat <= n and w <= lon <= e

def chs_gates():
    out = []
    for st in requests.get(f"{IWLS}/stations", timeout=60).json():
        if not inbox(st["latitude"], st["longitude"]):
            continue
        codes = {s["code"] for s in st.get("timeSeries", [])}
        if "wcp1-events" not in codes:
            continue
        meta = requests.get(f"{IWLS}/stations/{st['id']}/metadata", timeout=60).json()
        if meta.get("floodDirection") is None:
            continue
        out.append({"slug": st["officialName"].lower().replace(" ", "-"),
                    "source": "chs", "id": st["code"], "iwlsId": st["id"],
                    "lat": st["latitude"], "lon": st["longitude"],
                    "flood": meta["floodDirection"], "ebb": meta["ebbDirection"]})
        time.sleep(1)  # Be polite with API requests between metadata calls
    return out

def noaa_stations():
    out = []
    seen = set()  # Dedup on station id (MDAPI returns one row per currbin)
    js = requests.get(f"{MD}/stations.json?type=currentpredictions&units=english", timeout=120).json()
    for st in js["stations"]:
        if not inbox(st["lat"], st["lng"]) or st.get("type") != "H":
            continue
        if st["id"] in seen:
            continue
        seen.add(st["id"])
        # meanFloodDir/meanEbbDir come back with any currents_predictions data request
        r = requests.get(CP, params={"station": st["id"], "product": "currents_predictions",
                                     "date": "today", "range": "24", "interval": "MAX_SLACK",
                                     "units": "english", "time_zone": "gmt", "format": "json"},
                         timeout=60).json()
        cp = r.get("current_predictions", {})
        if not cp.get("cp"):
            continue
        # meanFloodDir/meanEbbDir are in the first entry of the cp array
        first_cp = cp["cp"][0]
        out.append({"slug": st["name"].lower().replace(" ", "-")[:40].strip("-"),
                    "source": "noaa", "id": st["id"], "lat": st["lat"], "lon": st["lng"],
                    "flood": float(first_cp["meanFloodDir"]), "ebb": float(first_cp["meanEbbDir"])})
    return out

if __name__ == "__main__":
    os.makedirs("data", exist_ok=True)
    stations = chs_gates() + noaa_stations()
    json.dump(stations, open("data/stations.json", "w"), indent=1)
    n_chs = sum(s["source"] == "chs" for s in stations)
    n_noaa = sum(s["source"] == "noaa" for s in stations)
    print(f"{len(stations)} truth stations ({n_chs} CHS, {n_noaa} NOAA)")
    assert len({s["id"] for s in stations}) == len(stations), "station id collision"
    assert len({s["slug"] for s in stations}) == len(stations), "slug collision"
