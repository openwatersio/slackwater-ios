#!/usr/bin/env -S uv run --script --with numpy,rasterio
"""Slackwater patch-pipeline — cross-section derivation (grown-patches spec §2).

inputs/<slug>.json + bathymetry tiles (data/tiles/<slug>/, gitignored, with
MANIFEST.json) -> passes/<slug>.json: refined thalweg, perpendicular sections,
A(x) at MWL, continuity scales A(anchor)/A(x).

Thalweg refinement = "deepest connected path", operationally: build sections
perpendicular to the hand-drawn seed, recenter each on its deepest sample,
rebuild sections perpendicular to the refined polyline once. "Connected" is
load-bearing: the run measured contains the station's own centre, relief must
beat MIN_RELIEF_M to move the line at all, and the lateral move per station is
slew-limited and then smoothed. Without those three the refinement chases
noise across the channel and pass 2 lays sections along it. The sensitivity
sweep (sensitivity.py) owns placement-error truncation.

Licence: tiles are never committed (NONNA clause 7 / BlueTopo per-tile
contributor check); this file copies MANIFEST provenance into the committed
pass artifact so the tile cache is disposable.
"""
import hashlib, json, math, os, sys
from datetime import datetime, timezone

import numpy as np

M_PER_DEG_LAT = 111320.0
CROSS_STEP_M = 10.0  # depth-sample step across a section
MIN_RELIEF_M = 2.0   # deepest must beat the seed point by this to move the thalweg
MAX_SLEW = 0.5       # thalweg lateral move per station, as a fraction of spacing
FLARE = 1.3          # mouth termination: first section wider than FLARE x throat ends the patch
THROAT_TOL = 1.1     # anchor width may exceed the strip minimum by this and still be "the throat"


def _m_per_deg_lon(lat):
    return M_PER_DEG_LAT * math.cos(math.radians(lat))


def _bearing_deg(p0, p1):
    """Initial bearing p0->p1, degrees true, flat-earth (passes are km-scale)."""
    dx = (p1[0] - p0[0]) * _m_per_deg_lon(p0[1])
    dy = (p1[1] - p0[1]) * M_PER_DEG_LAT
    return math.degrees(math.atan2(dx, dy)) % 360


def _walk(points, spacing_m):
    """Resample a polyline to ~spacing_m station points (lon/lat)."""
    out = [points[0]]
    carry = 0.0
    for p0, p1 in zip(points, points[1:]):
        seg = math.hypot((p1[0] - p0[0]) * _m_per_deg_lon(p0[1]),
                         (p1[1] - p0[1]) * M_PER_DEG_LAT)
        if seg <= 0.0:
            continue  # degenerate (duplicate) point: no distance to carry across
        d = carry
        while d + spacing_m <= seg:
            d += spacing_m
            f = d / seg
            out.append([p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f])
        carry = d - seg  # signed: how far the next mark overshoots into the next segment
    return out


def _offset_point(center, bearing_deg, offset_m):
    """Point offset_m to starboard of center, perpendicular to bearing."""
    perp = math.radians(bearing_deg + 90.0)
    return [center[0] + math.sin(perp) / _m_per_deg_lon(center[1]) * offset_m,
            center[1] + math.cos(perp) / M_PER_DEG_LAT * offset_m]


def _section(center, bearing_deg, half_width_m, depth_at):
    """Sample depth across the channel perpendicular to bearing.
    Returns (left, right, width_m, area_m2, deepest_offset_m, deepest_depth_m)
    or None if dry."""
    offsets = np.arange(-half_width_m, half_width_m + CROSS_STEP_M, CROSS_STEP_M)
    pts = [_offset_point(center, bearing_deg, o) for o in offsets]
    depths = np.array([depth_at(p[0], p[1]) for p in pts])
    wet = np.isfinite(depths) & (depths > 0)
    if not wet.any():
        return None
    # the channel is the contiguous wet run containing the center -- the water
    # this station is actually in. Growing the run from the deepest sample
    # instead lets a station on one side of an island measure the water on the
    # other side (Pass Island, Deception): a different body, not this channel.
    mid = len(offsets) // 2  # offset 0
    i0 = mid if wet[mid] else int(np.nanargmax(np.where(wet, depths, -np.inf)))
    lo = hi = i0
    while lo > 0 and wet[lo - 1]:
        lo -= 1
    while hi < len(wet) - 1 and wet[hi + 1]:
        hi += 1
    dpi = lo + int(np.argmax(depths[lo:hi + 1]))
    area = float(np.trapezoid(depths[lo:hi + 1], dx=CROSS_STEP_M))
    width = float((hi - lo) * CROSS_STEP_M)
    return pts[lo], pts[hi], width, area, float(offsets[dpi]), float(depths[dpi])


def _reach_mean(areas):
    """A(x) as the reach-mean cross-section area over +/- half a section
    spacing (spec 3, owner ruling 2026-08-21 third amendment): transport
    conservation is a reach statement, and a single transect at a sharp
    throat is placement-noisy (measured 12.7% anchor-area swing at
    Deception's 140 m gut vs 1.4-5.3% at Tacoma's 1370 m throat). Sections
    already sit at one-spacing intervals, so the window mean under a
    piecewise-linear model of A(x) between stations is just the 3-point
    weighted average of a station with its two neighbours -- Simpson-ish
    weights 0.25/0.5/0.25 (no need to re-sample new cross-sections at
    x +/- spacing/2; the existing stations already are that grid). Clamped
    at strip ends by renormalizing over whichever neighbour exists, so every
    output is still a true weighted mean (weights sum to 1), not a
    foreshortened sum that would bias the ends low."""
    n = len(areas)
    out = []
    for i in range(n):
        avail = [(j, w) for j, w in ((i - 1, 0.25), (i, 0.5), (i + 1, 0.25)) if 0 <= j < n]
        wsum = sum(w for _, w in avail)
        out.append(sum(areas[j] * w for j, w in avail) / wsum)
    return out


def build_pass(inputs, depth_at):
    """Pure core: inputs dict + depth_at(lon, lat)->metres-at-MWL (NaN=dry)."""
    spacing = inputs["section_spacing_m"]
    half_w = inputs["max_half_width_m"]

    # pass 1: sections on the seed, recenter on the deepest sample -- under two
    # constraints that make it a *connected* path rather than a sequence of
    # independent argmaxes. Without them the refined polyline runs across the
    # channel and pass 2 lays "perpendicular" sections along it.
    #   relief: in a flat reach "deepest" is a metre of noise that flips sides
    #           between stations; there the hand-drawn seed is the centerline.
    #   slew:   a real thalweg cannot move sideways faster than it advances.
    seed = _walk(inputs["thalweg_seed"], spacing)
    refined, prev_off = [], 0.0
    for i, c in enumerate(seed):
        nb = seed[max(i - 1, 0)], seed[min(i + 1, len(seed) - 1)]
        b = _bearing_deg(*nb)
        s = _section(c, b, half_w, depth_at)
        if not s:
            continue
        d_seed = depth_at(c[0], c[1])
        off = s[4] if s[5] > d_seed + MIN_RELIEF_M or not (d_seed > 0) else 0.0
        slew = spacing * MAX_SLEW
        off = min(max(off, prev_off - slew), prev_off + slew)
        prev_off = off
        refined.append(_offset_point(c, b, off))
    if len(refined) < 3:
        raise SystemExit(f"{inputs['slug']}: <3 wet sections — check tiles/inputs")
    # moving average (window 3), ends fixed: kills the remaining station-to-
    # station jitter before it becomes a pass-2 bearing
    refined = [refined[0]] + [[(p[0] + q[0] + r[0]) / 3.0, (p[1] + q[1] + r[1]) / 3.0]
                              for p, q, r in zip(refined, refined[1:], refined[2:])] + [refined[-1]]

    # pass 2: sections perpendicular to the refined thalweg
    stations = _walk(refined, spacing)
    sections = []
    for i, c in enumerate(stations):
        nb = stations[max(i - 1, 0)], stations[min(i + 1, len(stations) - 1)]
        b = _bearing_deg(*nb)
        s = _section(c, b, half_w, depth_at)
        if s is None:
            continue
        left, right, width, area = s[:4]
        sections.append({"center": [float(c[0]), float(c[1])], "bearing_deg": round(b, 1),
                         "width_m": round(width, 1), "area_m2": round(area, 1),
                         "left": [float(left[0]), float(left[1])],
                         "right": [float(right[0]), float(right[1])]})

    # A(x) for the speed scale: reach-mean, not the raw transect (spec 3,
    # owner ruling 2026-08-21 third amendment). Raw area_m2 stays in the doc
    # so both are auditable; scales are derived from area_reach_m2 only.
    # (Mouth termination/flare below is a WIDTH rule -- unaffected.)
    areas_reach = _reach_mean([s["area_m2"] for s in sections])
    for s, ar in zip(sections, areas_reach):
        s["area_reach_m2"] = round(ar, 1)

    # anchor section = nearest to the anchor station; flood-orientation assert
    a = inputs["anchor"]
    dists = [math.hypot((s["center"][0] - a["lon"]) * _m_per_deg_lon(a["lat"]),
                        (s["center"][1] - a["lat"]) * M_PER_DEG_LAT) for s in sections]
    k = int(np.argmin(dists))
    diff = abs((sections[k]["bearing_deg"] - a["flood_deg"] + 180) % 360 - 180)
    if diff > 60:
        raise SystemExit(f"{inputs['slug']}: thalweg bearing {sections[k]['bearing_deg']} vs "
                         f"anchor flood {a['flood_deg']} — seed must be drawn in the flood direction")

    a_area = sections[k]["area_reach_m2"]
    scales = [round(a_area / s["area_reach_m2"], 4) for s in sections]

    # Mouth termination (spec 3, owner ruling 2026-08-21): walking outward from
    # the anchor, the patch ends at the first section wider than FLARE x the
    # throat. Timing coherence dies at the flare, so the bounds are the
    # geometry's, not a judgment call. Throat reference = the anchor's own
    # width -- scale is 1 there by construction -- but only while the anchor
    # really is the narrowest water in the strip; otherwise fall back to the
    # strip minimum and say so.
    flare = float(inputs.get("flare_ratio", FLARE))
    min_w = min(s["width_m"] for s in sections)
    throat = sections[k]["width_m"]
    throat_ref = "anchor section"
    if throat > min_w * THROAT_TOL:
        throat, throat_ref = min_w, "strip minimum (anchor is not the throat)"
    limit = throat * flare
    lo = hi = k
    while lo > 0 and sections[lo - 1]["width_m"] <= limit:
        lo -= 1
    while hi < len(sections) - 1 and sections[hi + 1]["width_m"] <= limit:
        hi += 1
    return {
        "slug": inputs["slug"],
        "anchor": {**a, "section_index": k},
        "datum": {"reference": "MWL", "cd_to_mwl_m": inputs["cd_to_mwl_m"]},
        "section_spacing_m": spacing,
        "thalweg": [[float(p[0]), float(p[1])] for p in refined],
        "sections": sections,
        "scales": scales,
        "kept_range": [lo, hi],
        "flare_ratio": flare,
        "throat": {"width_m": throat, "reference": throat_ref, "limit_m": round(limit, 1)},
        "ends": inputs["ends"],
    }


def tile_depth_fn(tile_dir, tile_value, cd_to_mwl_m):
    """depth_at(lon, lat) over every GeoTIFF in tile_dir (WGS84-warped read)."""
    import rasterio
    from rasterio.warp import transform as rio_transform
    from rasterio.crs import CRS
    srcs = [rasterio.open(os.path.join(tile_dir, f))
            for f in sorted(os.listdir(tile_dir)) if f.lower().endswith((".tif", ".tiff"))]
    if not srcs:
        raise SystemExit(f"no GeoTIFFs in {tile_dir}")
    wgs = CRS.from_epsg(4326)

    def depth_at(lon, lat):
        for src in srcs:
            xs, ys = rio_transform(wgs, src.crs, [lon], [lat])
            row, col = src.index(xs[0], ys[0])
            if 0 <= row < src.height and 0 <= col < src.width:
                v = src.read(1, window=((row, row + 1), (col, col + 1)))[0, 0]
                if src.nodata is not None and v == src.nodata:
                    continue  # tiles overlap at seams; nodata here can be real data in the next tile
                d = -float(v) if tile_value == "elevation" else float(v)
                return d + cd_to_mwl_m
        return float("nan")
    return depth_at


def main(slug):
    inputs = json.load(open(f"inputs/{slug}.json"))
    tile_dir = f"data/tiles/{slug}"
    manifest = json.load(open(os.path.join(tile_dir, "MANIFEST.json")))
    for t in manifest["tiles"]:  # verify cache integrity before deriving anything
        got = hashlib.sha256(open(os.path.join(tile_dir, t["file"]), "rb").read()).hexdigest()
        if got != t["sha256"]:
            raise SystemExit(f"{t['file']}: sha256 mismatch — re-download, or update MANIFEST deliberately")
    depth_at = tile_depth_fn(tile_dir, inputs["tile_value"], inputs["cd_to_mwl_m"])
    out = build_pass(inputs, depth_at)
    out["generated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out["provenance"] = {"tiles": manifest["tiles"],
                         "inputs_sha256": hashlib.sha256(open(f"inputs/{slug}.json", "rb").read()).hexdigest()}
    os.makedirs("passes", exist_ok=True)
    json.dump(out, open(f"passes/{slug}.json", "w"), indent=1)
    print(f"{slug}: {len(out['sections'])} sections, anchor at index {out['anchor']['section_index']}, "
          f"scale range {min(out['scales'])}-{max(out['scales'])}\n"
          f"  kept_range {out['kept_range']} of [0, {len(out['sections']) - 1}] — "
          f"throat {out['throat']['width_m']} m ({out['throat']['reference']}), "
          f"flare {out['flare_ratio']} → limit {out['throat']['limit_m']} m")


if __name__ == "__main__":
    main(sys.argv[1])
