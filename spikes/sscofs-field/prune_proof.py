#!/usr/bin/env -S uv run --script --with numpy
"""Bundle-pruning proof (spec §10): can the backdrop fill's certified region
ship under the <=40 MB budget?

Vectorized numpy-lstsq SIZING fits (23-name shipping basis, mean term, hourly
60 d corpus) for every box element at once -- SIZING fits only; the shipping
fitter remains chs-glue's fitTides (`tools/FitValidation`, Task 5). Floors:
per-axis tidal R^2 >= 0.8 (elements below are uncertified -- weakly tidal
water is not painted); per-element constituent energy floor
amp >= max(2% of that element's max amplitude, 0.005 kn). Quantization: 5 B
per kept constituent per axis + 8 B/element header. Extrapolation to the
render region scales by certified-area density and is CAPPED by the
full-mesh element count (433,410) -- the earlier README's plain box-density
extrapolation overshot the full mesh and was called out in review.

Consumes: corpus/*.npz, mesh/elements.json, certified/certified.json,
samples/index.json + truth/stations.json (via certify.py's own
station_verdicts/grade_elements -- re-imported, not re-derived, so the D=2/5
km sensitivity sets use the exact same distance logic certified.json's D=3 km
set came from), Slackwater/Resources/chs-bundle.js.

Produces: certified/PRUNING.md.
"""
import glob
import json
import os
import subprocess

import numpy as np

from certify import grade_elements, station_verdicts

BASIS_NAMES = ["M2", "S2", "N2", "K2", "K1", "O1", "P1", "Q1", "M4", "MS4", "MN4",
               "2N2", "MU2", "NU2", "L2", "T2", "J1", "MM", "MSF", "MF", "M6", "S4", "M3"]

R2_FLOOR = 0.8
R2_SENSITIVITY = (0.7, 0.8, 0.9)
D_SENSITIVITY_M = (2000, 3000, 5000)
D_BASELINE_M = 3000
FULL_MESH_ELEMENTS = 433_410  # SSCOFS mesh total (mesh_subset.py / README.md)
RENDER_REGION_DEG2 = (125.5 - 122.0) * (50.6 - 47.0)  # Salish clip (report.py, #30)
KN_PER_MPS = 1.94384
BUNDLE_BUDGET_MB = 40
LABEL = "sizing fits (numpy lstsq) — not the shipping fitter"

_BASIS_SPEED_SCRIPT = r"""
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const lines = src.split("\n");
let cur = null; const entries = [];
for (const line of lines) {
  const nm = line.match(/"name":\s*"([^"]+)"/);
  const sp = line.match(/"speed":\s*([-\d.]+)/);
  const al = line.match(/"aliases":\s*\[([^\]]*)\]/);
  if (nm) { if (cur) entries.push(cur); cur = {name: nm[1]}; }
  if (sp && cur && cur.speed === undefined) cur.speed = parseFloat(sp[1]);
  if (al && cur) cur.aliases = [...al[1].matchAll(/"([^"]+)"/g)].map(x => x[1]);
}
if (cur) entries.push(cur);
const map = {};
for (const e of entries) {
  if (e.speed === undefined) continue;
  map[e.name] = e.speed;
  for (const a of (e.aliases || [])) if (!(a in map)) map[a] = e.speed;
}
console.log(JSON.stringify(map));
"""


def basis_speeds(bundle_path="../../Slackwater/Resources/chs-bundle.js"):
    """Basis constituent angular speeds (deg/hour), sourced from the shipping
    bundle.

    Path actually used (checked, not assumed): `node vm` loading the bundle
    exposes `CHSConstituents.BASIS` (the 23 bare names) but
    `Object.keys(CHSConstituents)` is only `["BASIS", "fit"]` -- no speeds
    table on the public surface. The speeds live in the bundle regardless,
    baked into each `defineConstituent(...)` record that `fit` closes over
    internally; MU2 has no record of its own and resolves via the alias on
    the "2MS2" entry. So: parse those name/speed/alias records straight out
    of chs-bundle.js's own source text -- the literal constants the shipping
    fitter runs against -- rather than falling back to a second-sourced,
    hand-typed NOAA table. (They match the standard published NOAA harmonic
    speeds to displayed precision, which is expected, not what's asserted.)
    """
    out = subprocess.run(["node", "-e", _BASIS_SPEED_SCRIPT, bundle_path],
                          capture_output=True, text=True, check=True).stdout
    table = json.loads(out)
    missing = [n for n in BASIS_NAMES if n not in table]
    if missing:
        raise RuntimeError(f"basis speeds missing from {bundle_path}: {missing}")
    return {n: table[n] for n in BASIS_NAMES}


def load_corpus(corpus_dir="corpus"):
    """Concatenate + sort all corpus/*.npz shards by t (epoch seconds).
    Filenames are batch labels, never time keys. Returns (t, u_kn, v_kn)."""
    ts, us, vs = [], [], []
    for path in sorted(glob.glob(os.path.join(corpus_dir, "*.npz"))):
        d = np.load(path)
        ts.append(d["t"])
        us.append(d["u"])
        vs.append(d["v"])
    t = np.concatenate(ts)
    u = np.concatenate(us, axis=0)
    v = np.concatenate(vs, axis=0)
    order = np.argsort(t)
    t = t[order]
    u = (u[order] * KN_PER_MPS).astype(np.float32)
    v = (v[order] * KN_PER_MPS).astype(np.float32)
    return t, u, v


def design_matrix(t, speeds_deg_per_hour, epoch=None):
    """A [n_hours, 2*len(speeds)+1]: mean term + cos/sin at each basis speed.
    t in epoch seconds; converted to hours since `epoch` (default t[0])."""
    if epoch is None:
        epoch = t[0]
    t_hours = (t - epoch) / 3600.0
    cols = [np.ones_like(t_hours)]
    for speed in speeds_deg_per_hour:
        theta = np.radians(speed) * t_hours
        cols.append(np.cos(theta))
        cols.append(np.sin(theta))
    return np.stack(cols, axis=1)


def fit_elements(t, U, speeds_deg_per_hour):
    """Vectorized sizing fit for every column (element) of U [n_hours,
    n_elements] at once: constants = pinv(A) @ U, one matmul per axis. NaN
    rows (missing hours -- none in this corpus, checked) dropped before the
    fit. Returns (const [1+2*len(speeds), n_elements], r2 [n_elements])."""
    mask = ~np.isnan(U).any(axis=1)
    t_use, U_use = t[mask], U[mask]
    A = design_matrix(t_use, speeds_deg_per_hour, epoch=t[0])
    pinv_a = np.linalg.pinv(A)
    const = pinv_a @ U_use
    pred = A @ const
    resid = U_use - pred
    ss_res = np.sum(resid ** 2, axis=0)
    ss_tot = np.sum((U_use - U_use.mean(axis=0, keepdims=True)) ** 2, axis=0)
    with np.errstate(invalid="ignore", divide="ignore"):
        r2 = np.where(ss_tot > 0, 1.0 - ss_res / ss_tot, 0.0)
    return const, r2


def energy_floor_keep(amps):
    """Per-element constituent energy floor (§10): keep constituent i iff
    amp[i] >= max(2% of this element's max amplitude, 0.005 kn)."""
    amps = np.asarray(amps)
    floor = max(0.02 * float(amps.max()), 0.005) if amps.size else 0.005
    return amps >= floor


def bundle_bytes(kept_counts):
    """5 B per kept constituent per axis + 8 B/element header."""
    return sum(8 + 5 * 2 * k for k in kept_counts)


def describe(arr):
    arr = np.asarray(arr)
    if arr.size == 0:
        return {"n": 0}
    p = np.percentile(arr, [5, 25, 50, 75, 95])
    return {"n": int(arr.size), "min": float(arr.min()), "p05": float(p[0]),
            "p25": float(p[1]), "median": float(p[2]), "p75": float(p[3]),
            "p95": float(p[4]), "max": float(arr.max()), "mean": float(arr.mean())}


def certified_ids_by_distance():
    """Certified-element id sets at D = 2/3/5 km, via certify.py's own
    station_verdicts/grade_elements (not re-derived distance logic)."""
    elements = json.load(open("mesh/elements.json"))["elements"]
    index = json.load(open("samples/index.json"))
    truth_by_slug = {s["slug"]: s for s in json.load(open("truth/stations.json"))}
    stations = station_verdicts(index)
    for s in stations:
        t = truth_by_slug[s["slug"]]
        s["lat"], s["lon"] = t["lat"], t["lon"]

    out = {}
    for D in D_SENSITIVITY_M:
        statuses = grade_elements(elements, stations, D)
        out[D] = {e["i"] for e, st in zip(elements, statuses) if st == "yes"}
    return elements, out


def main():
    print(f"[{LABEL}] loading basis speeds...")
    speeds = basis_speeds()
    speed_list = [speeds[n] for n in BASIS_NAMES]

    print(f"[{LABEL}] loading + sorting corpus...")
    t, u_kn, v_kn = load_corpus()
    print(f"  {len(t)} hourly samples, {u_kn.shape[1]} box elements")

    print(f"[{LABEL}] fitting u axis (pinv(A) @ U)...")
    const_u, r2_u = fit_elements(t, u_kn, speed_list)
    print(f"[{LABEL}] fitting v axis (pinv(A) @ U)...")
    const_v, r2_v = fit_elements(t, v_kn, speed_list)
    min_r2 = np.minimum(r2_u, r2_v)

    degenerate_frac = float((min_r2 < 0.5).mean())
    if degenerate_frac > 0.9:
        print(f"WARNING: {degenerate_frac:.0%} of box elements have min-axis R^2 < 0.5 "
              "-- possible units/phase bug. Inspect before trusting the verdict below.")

    els = json.load(open("mesh/elements.json"))
    box = els["box"]
    box_deg2 = (box[2] - box[0]) * (box[3] - box[1])
    elem_ids = np.array([e["i"] for e in els["elements"]])

    certified = json.load(open("certified/certified.json"))
    elements, cert_ids_by_d = certified_ids_by_distance()
    assert elements == els["elements"], "mesh/elements.json order drifted between loads"

    # Sanity: the recomputed D=2/3/5 km sets must match certified.json's own
    # recorded counts (and the D=3 km set exactly) -- catches drift between
    # this script's re-import and certify.py's own last run.
    for D in D_SENSITIVITY_M:
        recorded = certified["sensitivity"][str(D)]
        recomputed = len(cert_ids_by_d[D])
        assert recomputed == recorded, (
            f"D={D}: recomputed {recomputed} certified elements != "
            f"certified.json's recorded {recorded} -- re-run certify.py")
    assert cert_ids_by_d[D_BASELINE_M] == set(certified["elements"]), \
        "D=3000 recomputed set != certified.json's elements"

    # Per-element kept-constituent counts -- independent of the D/R^2
    # thresholds below, so computed once for all 73,550 elements and then
    # filtered per sensitivity config.
    amp_u = np.hypot(const_u[1::2, :], const_u[2::2, :])  # [23, n_elements]
    amp_v = np.hypot(const_v[1::2, :], const_v[2::2, :])
    floor_u = np.maximum(0.02 * amp_u.max(axis=0), 0.005)
    floor_v = np.maximum(0.02 * amp_v.max(axis=0), 0.005)
    keep = (amp_u >= floor_u[None, :]) | (amp_v >= floor_v[None, :])  # kept if either axis
    kept_counts_all = keep.sum(axis=0)

    def evaluate(D, r2_floor):
        cert_mask = np.isin(elem_ids, list(cert_ids_by_d[D]))
        survive = cert_mask & (min_r2 >= r2_floor)
        n_cert, n_survive = int(cert_mask.sum()), int(survive.sum())
        kept = kept_counts_all[survive]
        measured_bytes = bundle_bytes(kept.tolist())
        density = n_survive / box_deg2
        n_render_raw = density * RENDER_REGION_DEG2
        n_render_capped = min(n_render_raw, FULL_MESH_ELEMENTS)
        avg_bytes = measured_bytes / n_survive if n_survive else 0.0
        extrap_bytes = n_render_capped * avg_bytes
        return {"D": D, "r2_floor": r2_floor, "n_cert": n_cert, "n_survive": n_survive,
                "kept": kept, "measured_mb": measured_bytes / 1e6,
                "n_render_raw": n_render_raw, "n_render_capped": n_render_capped,
                "extrap_mb": extrap_bytes / 1e6}

    baseline = evaluate(D_BASELINE_M, R2_FLOOR)
    d_sensitivity = [evaluate(D, R2_FLOOR) for D in D_SENSITIVITY_M]
    r2_sensitivity = [evaluate(D_BASELINE_M, f) for f in R2_SENSITIVITY]

    os.makedirs("certified", exist_ok=True)
    write_report(speeds, len(t), r2_u, r2_v, min_r2, certified, baseline,
                 d_sensitivity, r2_sensitivity, box_deg2, degenerate_frac)
    print(open("certified/PRUNING.md").read())


def write_report(speeds, n_hours, r2_u, r2_v, min_r2, certified, baseline,
                  d_sensitivity, r2_sensitivity, box_deg2, degenerate_frac):
    verdict = "PASS" if baseline["extrap_mb"] <= BUNDLE_BUDGET_MB else "FAIL"

    with open("certified/PRUNING.md", "w") as out:
        out.write("# Bundle-pruning proof (spec §10)\n\n")
        out.write(f"All fitted/measured quantities below are **{LABEL}** — chs-glue's "
                   "fitTides remains the shipping fitter; this script sizes the bundle.\n\n")

        out.write("## Basis speeds\n\n")
        out.write("`node vm`-confirmed `CHSConstituents` public surface is `{BASIS, fit}` "
                   "only (no speeds table); speeds parsed from the bundle's own embedded "
                   "`defineConstituent(...)` records instead of a hand-typed NOAA table "
                   "(MU2 resolved via its \"2MS2\" alias). 23/23 basis names resolved: "
                   f"{', '.join(f'{n}={speeds[n]:g}°/h' for n in BASIS_NAMES)}\n\n")

        out.write(f"## Corpus\n\n{n_hours} hourly samples ({n_hours / 24:.0f} days), "
                   f"{len(min_r2)} box elements, box area {box_deg2:.3f} deg².\n\n")

        out.write(f"## R² distribution — {LABEL}\n\n")
        out.write("| population | n | min | p05 | p25 | median | p75 | p95 | max | mean |\n")
        out.write("|---|---|---|---|---|---|---|---|---|---|\n")
        d = describe(r2_u)
        out.write(f"| u axis, all {d['n']} box elements | {d['n']} | {d['min']:.3f} | "
                   f"{d['p05']:.3f} | {d['p25']:.3f} | {d['median']:.3f} | {d['p75']:.3f} | "
                   f"{d['p95']:.3f} | {d['max']:.3f} | {d['mean']:.3f} |\n")
        d = describe(r2_v)
        out.write(f"| v axis, all {d['n']} box elements | {d['n']} | {d['min']:.3f} | "
                   f"{d['p05']:.3f} | {d['p25']:.3f} | {d['median']:.3f} | {d['p75']:.3f} | "
                   f"{d['p95']:.3f} | {d['max']:.3f} | {d['mean']:.3f} |\n")
        d = describe(min_r2)
        out.write(f"| min(u,v), all {d['n']} box elements | {d['n']} | {d['min']:.3f} | "
                   f"{d['p05']:.3f} | {d['p25']:.3f} | {d['median']:.3f} | {d['p75']:.3f} | "
                   f"{d['p95']:.3f} | {d['max']:.3f} | {d['mean']:.3f} |\n\n")
        if degenerate_frac > 0.9:
            out.write(f"**WARNING:** {degenerate_frac:.0%} of box elements have min-axis "
                       "R² < 0.5 — check for a units/phase bug before trusting the verdict.\n\n")

        out.write(f"## Elements surviving the R² floor — {LABEL}\n\n")
        out.write(f"D = {baseline['D']} m, R² floor = {baseline['r2_floor']}: "
                   f"{baseline['n_cert']} certified box elements, "
                   f"**{baseline['n_survive']}** survive the R² floor "
                   f"({baseline['n_survive'] / baseline['n_cert'] * 100:.1f}% of certified).\n\n")

        out.write(f"## Constituents/element after the energy floor — {LABEL}\n\n")
        kd = describe(baseline["kept"])
        if kd["n"]:
            out.write(f"Surviving elements (n={kd['n']}): kept constituents per element — "
                       f"min {kd['min']:.0f}, p25 {kd['p25']:.1f}, median {kd['median']:.1f}, "
                       f"p75 {kd['p75']:.1f}, max {kd['max']:.0f}, mean {kd['mean']:.2f} "
                       f"(of 23 possible).\n\n")
        else:
            out.write("No surviving elements — nothing to distribute.\n\n")

        out.write(f"## Measured bytes — certified box elements — {LABEL}\n\n")
        out.write(f"{baseline['n_survive']} surviving elements → "
                   f"**{baseline['measured_mb']:.3f} MB** measured, in-box, no extrapolation.\n\n")

        out.write(f"## Render-region extrapolation, capped at {FULL_MESH_ELEMENTS:,} — {LABEL}\n\n")
        out.write(f"Certified-area density ({baseline['n_survive']} / {box_deg2:.3f} deg²) × "
                   f"render region ({RENDER_REGION_DEG2:.2f} deg², Salish clip) = "
                   f"{baseline['n_render_raw']:,.0f} elements raw, capped to "
                   f"**{baseline['n_render_capped']:,.0f}** (full-mesh element count). "
                   f"→ **{baseline['extrap_mb']:.2f} MB** extrapolated.\n\n")

        out.write(f"## Verdict vs {BUNDLE_BUDGET_MB} MB (D = {baseline['D']} m, "
                   f"R² floor = {baseline['r2_floor']})\n\n")
        out.write(f"**{verdict}** — {baseline['extrap_mb']:.2f} MB extrapolated "
                   f"(capped render-region estimate) vs {BUNDLE_BUDGET_MB} MB budget.\n\n")

        out.write(f"## Sensitivity — D = 2/3/5 km (R² floor fixed at {R2_FLOOR}) — {LABEL}\n\n")
        out.write("| D (m) | certified | survive R² floor | measured MB (box) | "
                   "extrapolated MB (capped) | vs 40 MB |\n|---|---|---|---|---|---|\n")
        for row in d_sensitivity:
            v = "PASS" if row["extrap_mb"] <= BUNDLE_BUDGET_MB else "FAIL"
            out.write(f"| {row['D']} | {row['n_cert']} | {row['n_survive']} | "
                       f"{row['measured_mb']:.3f} | {row['extrap_mb']:.2f} | {v} |\n")

        out.write(f"\n## Sensitivity — R² floor = 0.7/0.8/0.9 (D fixed at "
                   f"{D_BASELINE_M} m) — {LABEL}\n\n")
        out.write("| R² floor | certified | survive R² floor | measured MB (box) | "
                   "extrapolated MB (capped) | vs 40 MB |\n|---|---|---|---|---|---|\n")
        for row in r2_sensitivity:
            v = "PASS" if row["extrap_mb"] <= BUNDLE_BUDGET_MB else "FAIL"
            out.write(f"| {row['r2_floor']} | {row['n_cert']} | {row['n_survive']} | "
                       f"{row['measured_mb']:.3f} | {row['extrap_mb']:.2f} | {v} |\n")


if __name__ == "__main__":
    main()
