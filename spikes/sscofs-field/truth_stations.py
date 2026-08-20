#!/usr/bin/env -S uv run --script --with requests
"""Build the truth-station table for the box: CHS gates (IWLS metadata axis) + NOAA type-H current stations (currents_predictions metadata axis)."""
import json, os, requests, time

BOX = (-123.95, 48.30, -122.55, 49.25)
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
    js = requests.get(f"{MD}/stations.json?type=currentpredictions&units=english", timeout=120).json()
    for st in js["stations"]:
        if not inbox(st["lat"], st["lng"]) or st.get("type") != "H":
            continue
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
    os.makedirs("truth", exist_ok=True)
    stations = chs_gates() + noaa_stations()
    json.dump(stations, open("truth/stations.json", "w"), indent=1)
    print(f"{len(stations)} truth stations "
          f"({sum(s['source']=='chs' for s in stations)} CHS, "
          f"{sum(s['source']=='noaa' for s in stations)} NOAA)")
    assert any("dodd" in s["slug"] for s in stations), "Dodd Narrows missing — box or filter wrong"
    assert any("active" in s["slug"] for s in stations), "Active Pass missing"
