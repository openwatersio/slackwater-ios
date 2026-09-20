# test_certify.py — run: uv run --with pytest,numpy pytest -q test_certify.py
#
# Synthetic geometry pinning every branch of grade_elements (§4a):
#   PASS station at (lat0, lon0); FAIL station 4 km east; UNSCOREABLE station 4 km
#   north. Distances computed with the spike's flat-earth convention (x111320,
#   cos(lat) on lon, using each station's own lat for the cos term — matches
#   make_samples.elements_near).
import math

from certify import grade_elements

LAT0, LON0 = 48.70, -123.00
M_PER_DEG_LAT = 111320.0


def _dlat_deg(km, lat_deg):
    return (km * 1000.0) / M_PER_DEG_LAT


def _dlon_deg(km, lat_deg):
    return (km * 1000.0) / (M_PER_DEG_LAT * math.cos(math.radians(lat_deg)))


PASS_LAT, PASS_LON = LAT0, LON0
FAIL_LAT, FAIL_LON = LAT0, LON0 + _dlon_deg(4.0, LAT0)
UNSC_LAT, UNSC_LON = LAT0 + _dlat_deg(4.0, LAT0), LON0

STATIONS = [
    {"slug": "pass-station", "lat": PASS_LAT, "lon": PASS_LON, "verdict": "PASS", "speed_med": 0.2},
    {"slug": "fail-station", "lat": FAIL_LAT, "lon": FAIL_LON, "verdict": "FAIL", "speed_med": 0.8},
    {"slug": "unsc-station", "lat": UNSC_LAT, "lon": UNSC_LON, "verdict": "UNSCOREABLE", "speed_med": None},
]

# e4: exact-km offset from PASS solved so dist(e4,PASS)=2.5 km, dist(e4,FAIL)=3.5 km
# (PASS at km-origin, FAIL 4 km east): x=1.25, y=sqrt(2.5^2-1.25^2)
E4_X_KM, E4_Y_KM = 1.25, math.sqrt(2.5 ** 2 - 1.25 ** 2)

ELEMENTS = [
    # 1 km south of PASS → nearest PASS (1 km) → certified
    {"i": 1, "lat": PASS_LAT - _dlat_deg(1.0, LAT0), "lon": PASS_LON},
    # 1 km east of FAIL → nearest FAIL (1 km) → masked
    {"i": 2, "lat": FAIL_LAT, "lon": FAIL_LON + _dlon_deg(1.0, LAT0)},
    # on the PASS-FAIL axis, 2.1 km from PASS / 1.9 km from FAIL → nearest FAIL → masked
    {"i": 3, "lat": PASS_LAT, "lon": PASS_LON + _dlon_deg(2.1, LAT0)},
    # 2.5 km from PASS, 3.5 km from FAIL → nearest PASS, within D=3km → certified
    {"i": 4, "lat": PASS_LAT + _dlat_deg(E4_Y_KM, LAT0), "lon": PASS_LON + _dlon_deg(E4_X_KM, LAT0)},
    # 1 km north of the UNSCOREABLE station, ~5 km from PASS/FAIL → UNSCOREABLE grades
    # nothing, nearest *scoreable* station is >D → uncertified
    {"i": 5, "lat": UNSC_LAT + _dlat_deg(1.0, LAT0), "lon": UNSC_LON},
    # 10 km from everything → uncertified
    {"i": 6, "lat": PASS_LAT - _dlat_deg(10.0, LAT0), "lon": PASS_LON - _dlon_deg(10.0, LAT0)},
]

D_M = 3000  # spec §4a default


def test_grade_elements_branches():
    statuses = grade_elements(ELEMENTS, STATIONS, D_M)
    expected = {
        1: "yes",     # 1 km from PASS
        2: "masked",  # 1 km from FAIL
        3: "masked",  # equidistant-ish, nearest-FAIL
        4: "yes",     # 2.5 km from PASS (FAIL farther at 3.5 km)
        5: "none",    # only near UNSCOREABLE, which grades nothing
        6: "none",    # 10 km from everything
    }
    got = {e["i"]: s for e, s in zip(ELEMENTS, statuses)}
    assert got == expected


def test_grade_elements_all_unscoreable_grades_nothing():
    only_unsc = [s for s in STATIONS if s["verdict"] == "UNSCOREABLE"]
    statuses = grade_elements(ELEMENTS, only_unsc, D_M)
    assert set(statuses) == {"none"}


def test_grade_elements_sensitivity_shrinks_with_smaller_d():
    # e4 is 2.5 km from PASS: certified at D=3000 but not at D=2000.
    at_3000 = grade_elements(ELEMENTS, STATIONS, 3000)
    at_2000 = grade_elements(ELEMENTS, STATIONS, 2000)
    assert at_3000[3] == "yes"
    assert at_2000[3] == "none"
