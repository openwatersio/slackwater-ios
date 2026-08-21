#!/usr/bin/env -S uv run --script --with numpy
"""Slackwater fill-pipeline — Task 4: region survivors (spec §2/§4a, Fill
Phase B). Run from tools/fill-pipeline/.

Pipeline (task-4-brief.md):

  Stage 1 (certify):   data/verdicts + data/index.json + data/stations.json
                        -> station_verdicts -> grade all 311,447 mesh
                        elements at D=2/3/5 km -> certified set (D=3000,
                        spec §4a default).
  Stage 2 (prefilter):  numpy vectorized lstsq (design_matrix/fit_elements,
                        adapted from prune_proof.py -- see load_corpus_columns
                        docstring for what changed and why) over the
                        certified elements only -> shortlist where
                        prefilter-R^2 >= 0.7 on both axes (loose on purpose;
                        this is a cheap triage, not the floor).
  Stage 3 (node fit):   stream each shortlisted element's full 190-day u/v
                        series through fit_batch.mjs (the committed
                        chs-bundle.js/chs-glue.js shipping fitter) ->
                        data/fits/fits.jsonl. Resumable: elems already
                        present in that file are skipped on a re-run.
  Stage 4 (final floor): r2 = 1 - (rms^2 * n) / sum((v-mean(v))^2), n =
                        len(t) (constant across elements -- see the R^2
                        docstring below for why this is exact, not an
                        approximation). Survivors = node-fit R^2 >= 0.8 on
                        BOTH axes -> data/survivors.json + data/SURVIVORS.md.

Single-implementation rule: §4a grading (station_verdicts/grade_elements)
is imported from spikes/sscofs-field/certify.py, never forked. The numpy
prefilter (design_matrix/fit_elements) is imported from
spikes/sscofs-field/prune_proof.py for the same reason; only the corpus
loader is adapted (prune_proof loads every column, this loads a column
subset -- see load_corpus_columns).
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKE_DIR = os.path.join(HERE, "../../spikes/sscofs-field")
sys.path.insert(0, SPIKE_DIR)  # single-implementation rule (see module docstring)
from certify import grade_elements, station_verdicts  # noqa: E402
from prune_proof import BASIS_NAMES, basis_speeds, fit_elements  # noqa: E402

D_M = 3000  # spec §4a default (certified set + survivors.json's D_m)
SENSITIVITY_D_M = (2000, 3000, 5000)
PREFILTER_R2_FLOOR = 0.7  # loose on purpose -- final floor is the node fit
NODE_R2_FLOOR = 0.8  # spec §2 shipping-fit floor, both axes
KN_PER_MPS = 1.94384
PROGRESS_EVERY = 1000


# ---------------------------------------------------------------- Stage 1 --

def stage1_certify(data_dir):
    mesh = json.load(open(os.path.join(data_dir, "mesh.json")))
    elements = mesh["elements"]
    index = json.load(open(os.path.join(data_dir, "index.json")))
    truth_by_slug = {s["slug"]: s for s in json.load(open(os.path.join(data_dir, "stations.json")))}

    stations = station_verdicts(index, results_dir=os.path.join(data_dir, "verdicts"))
    for s in stations:
        t = truth_by_slug[s["slug"]]
        s["lat"], s["lon"] = t["lat"], t["lon"]

    statuses_by_d = {D: grade_elements(elements, stations, D) for D in SENSITIVITY_D_M}
    counts_by_d = {
        D: {k: statuses.count(k) for k in ("yes", "masked", "none")}
        for D, statuses in statuses_by_d.items()
    }
    return mesh, elements, stations, statuses_by_d, counts_by_d


# ---------------------------------------------------------------- Stage 2 --

def load_corpus_columns(corpus_dir, columns):
    """Adapted from prune_proof.py's load_corpus: same concatenate-then-
    sort-by-t + m/s->kn convention, but slices each day file down to
    `columns` (column positions into mesh.json's elements list, i.e. the
    corpus's own column index -- see task-4-brief.md's "column k of u/v =
    position k in mesh.json's elements list") right after loading each
    file, rather than after concatenating the full 311,447-column corpus.
    Reading each npz still costs a full-file decode (npz arrays aren't
    partial-readable), but slicing early keeps the concatenated result
    proportional to len(columns) instead of the full mesh -- the certified
    set is a small fraction of 311,447 elements, so this is the difference
    between a multi-GB and a whole-corpus-sized intermediate array."""
    columns = np.asarray(columns)
    ts, us, vs = [], [], []
    files = sorted(glob.glob(os.path.join(corpus_dir, "*.npz")))
    if not files:
        raise ValueError(f"no corpus files in {corpus_dir}")
    for path in files:
        d = np.load(path)
        ts.append(d["t"])
        us.append(d["u"][:, columns])
        vs.append(d["v"][:, columns])
    t = np.concatenate(ts)
    u = np.concatenate(us, axis=0)
    v = np.concatenate(vs, axis=0)
    order = np.argsort(t)
    t = t[order]
    u = (u[order] * KN_PER_MPS).astype(np.float32)
    v = (v[order] * KN_PER_MPS).astype(np.float32)
    nan_u, nan_v = int(np.isnan(u).sum()), int(np.isnan(v).sum())
    if nan_u or nan_v:
        raise ValueError(f"corpus has NaN samples (u={nan_u}, v={nan_v}) -- "
                          "prune_proof.fit_elements assumes none")
    return t, u, v


def stage2_prefilter(data_dir, certified_positions):
    t, u_kn, v_kn = load_corpus_columns(os.path.join(data_dir, "corpus"), certified_positions)
    speeds = basis_speeds(os.path.join(HERE, "..", "..", "Slackwater", "Resources", "chs-bundle.js"))
    speed_list = [speeds[n] for n in BASIS_NAMES]
    _, r2_u = fit_elements(t, u_kn, speed_list)
    _, r2_v = fit_elements(t, v_kn, speed_list)
    min_r2 = np.minimum(r2_u, r2_v)
    shortlist_mask = min_r2 >= PREFILTER_R2_FLOOR
    return t, u_kn, v_kn, shortlist_mask


# ---------------------------------------------------------------- Stage 3 --

def load_done(out_path):
    """Resumability: (elem, axis) pairs already present in fits.jsonl are
    skipped on a re-run. A trailing truncated line (killed mid-write) is
    dropped and the file truncated back to its last complete line, so a
    resume never leaves a corrupt tail behind."""
    if not os.path.exists(out_path):
        return set()
    done = set()
    valid_end = 0
    with open(out_path, "rb") as fh:
        pos = 0
        for raw in fh:
            pos += len(raw)
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                break
            done.add((row["elem"], row["axis"]))
            valid_end = pos
    with open(out_path, "r+b") as fh:
        fh.truncate(valid_end)
    return done


def stage3_node_fits(shortlist_elems, shortlist_cols, t, u_kn, v_kn, out_path):
    """Streams {elem, axis, samples} JSONL through fit_batch.mjs via real
    files (not pipes) for stdin/stdout -- sidesteps the pipe-buffer deadlock
    a large bidirectional stream could hit, and Node writes to a redirected
    *file* synchronously (unlike a pipe), so a killed run leaves at most one
    torn trailing line, which load_done()'s truncation already handles.
    Progress is polled via the growing output file's line count -- logged
    every PROGRESS_EVERY fits, not merely every N seconds."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    done = load_done(out_path)
    baseline = len(done)

    t_ms = (t * 1000.0).astype(np.int64)
    pending_path = out_path + ".pending_in"
    n_pending = 0
    with open(pending_path, "w") as fh:
        for elem, col in zip(shortlist_elems, shortlist_cols):
            for axis, arr in (("u", u_kn), ("v", v_kn)):
                if (elem, axis) in done:
                    continue
                samples = [{"t": int(tm), "v": float(val)} for tm, val in zip(t_ms, arr[:, col])]
                fh.write(json.dumps({"elem": elem, "axis": axis, "samples": samples}) + "\n")
                n_pending += 1

    if n_pending == 0:
        os.remove(pending_path)
        print(f"stage 3: nothing pending, {baseline} fits already in {out_path}")
        return

    print(f"stage 3: {n_pending} fits pending ({baseline} already done) -> {out_path}")
    t0 = time.time()
    with open(pending_path, "rb") as in_fh, open(out_path, "ab") as out_fh:
        proc = subprocess.Popen(["node", os.path.join(HERE, "fit_batch.mjs")],
                                 stdin=in_fh, stdout=out_fh, cwd=HERE)
        last_logged = 0
        while proc.poll() is None:
            time.sleep(5)
            cur = sum(1 for _ in open(out_path, "rb"))
            done_now = cur - baseline
            if done_now // PROGRESS_EVERY > last_logged // PROGRESS_EVERY:
                elapsed = time.time() - t0
                rate = done_now / elapsed if elapsed > 0 else 0
                eta = (n_pending - done_now) / rate if rate > 0 else float("nan")
                print(f"  node fits: {done_now}/{n_pending} "
                      f"({elapsed:.0f}s elapsed, ~{eta:.0f}s remaining)", flush=True)
                last_logged = done_now
        ret = proc.wait()
    os.remove(pending_path)
    if ret != 0:
        raise RuntimeError(f"fit_batch.mjs exited {ret}")
    elapsed = time.time() - t0
    print(f"stage 3: done, {n_pending} fits in {elapsed:.0f}s "
          f"({n_pending / elapsed:.1f}/s)" if elapsed > 0 else "stage 3: done")


# ---------------------------------------------------------------- Stage 4 --

def r2_from_rms(rms, n, values):
    """r2 = 1 - SS_res/SS_tot. chs-bundle.js's fit() computes
    `rms = sqrt(sum(residual^2) / samples.length)` (Slackwater/Resources/
    chs-bundle.js:6472) -- no degrees-of-freedom adjustment, no filtering of
    the input samples -- so SS_res = rms^2 * n exactly, with n the sample
    count *we* sent (constant across elements: the full corpus length).
    SS_tot is computed from those same values. This is exact given the
    fitter's own rms, not an approximation -- see task-4-brief.md's
    'simpler and correct' note."""
    ss_res = (rms ** 2) * n
    ss_tot = float(np.sum((values - values.mean()) ** 2))
    if ss_tot <= 0:
        return 0.0
    return 1.0 - ss_res / ss_tot


def build_survivors(fits_path, shortlist_elems, shortlist_cols, t, u_kn, v_kn):
    """shortlist_elems[k]/shortlist_cols[k] are the mesh element id and its
    matching u_kn/v_kn column for the k-th shortlisted element (same order,
    built together in main()). Reads fits.jsonl, computes r2 per (elem,
    axis) via r2_from_rms, keeps elements with r2 >= NODE_R2_FLOOR on both
    axes."""
    n = len(t)
    rows_by_elem = {}
    n_error = 0
    unseparable_seen = set()
    with open(fits_path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if "error" in row:
                n_error += 1
                continue
            rows_by_elem.setdefault(row["elem"], {})[row["axis"]] = row
            for pair in row.get("unseparable") or []:
                unseparable_seen.add(pair)

    col_by_elem = dict(zip(shortlist_elems, shortlist_cols))
    survivors = []
    for elem, axes in rows_by_elem.items():
        if "u" not in axes or "v" not in axes:
            continue
        col = col_by_elem.get(elem)
        if col is None:
            continue
        r2_u = r2_from_rms(axes["u"]["rms"], n, u_kn[:, col])
        r2_v = r2_from_rms(axes["v"]["rms"], n, v_kn[:, col])
        if r2_u >= NODE_R2_FLOOR and r2_v >= NODE_R2_FLOOR:
            survivors.append({
                "i": elem,
                "constituents_u": axes["u"]["constituents"],
                "constituents_v": axes["v"]["constituents"],
                "r2_u": r2_u,
                "r2_v": r2_v,
                # Z0 mean-flow term (chs-glue.js's fitTides "offset", kn) --
                # carried through so the shipped fill isn't a zero-mean
                # approximation of a real, nonzero mean flow. See pack.py's
                # build_header offset note for the corpus-window caveat.
                "offset_u": axes["u"]["offset"],
                "offset_v": axes["v"]["offset"],
            })
    survivors.sort(key=lambda e: e["i"])
    return survivors, n_error, sorted(unseparable_seen)


# --------------------------------------------------------------- Reporting --

def write_survivors_json(path, survivors, counts_by_d):
    out = {
        "D_m": D_M,
        "counts": {str(D): c for D, c in counts_by_d.items()},
        "elements": survivors,
    }
    with open(path, "w") as fh:
        json.dump(out, fh, indent=1)


def write_report(path, stations, counts_by_d, n_certified, n_shortlist,
                  survivors, n_error, unseparable_seen, seymour_dodd):
    n_pass = sum(1 for s in stations if s["verdict"] == "PASS")
    n_fail = sum(1 for s in stations if s["verdict"] == "FAIL")
    n_unsc = sum(1 for s in stations if s["verdict"] == "UNSCOREABLE")
    n_scoreable = n_pass + n_fail
    n_matrixed = len(stations)

    with open(path, "w") as out:
        out.write("# Region survivors (spec §2/§4a, Fill Phase B Task 4)\n\n")

        out.write(f"## Station verdicts ({n_matrixed} matrixed of 149 truth stations)\n\n")
        out.write(f"- PASS: {n_pass}\n- FAIL: {n_fail}\n- UNSCOREABLE: {n_unsc}\n"
                   f"- scoreable (PASS+FAIL): {n_scoreable}\n\n")
        out.write("| station | verdict | speed_med (kn) |\n|---|---|---|\n")
        for s in stations:
            sm = f"{s['speed_med']:.2f}" if s["speed_med"] is not None else "-"
            out.write(f"| {s['slug']} | {s['verdict']} | {sm} |\n")

        out.write(f"\n## Certified elements by D (of 311,447 region elements)\n\n")
        out.write("| D (m) | yes (certified) | masked | none | certified % |\n|---|---|---|---|---|\n")
        for D in SENSITIVITY_D_M:
            c = counts_by_d[D]
            total = c["yes"] + c["masked"] + c["none"]
            out.write(f"| {D} | {c['yes']} | {c['masked']} | {c['none']} | "
                       f"{c['yes'] / total * 100:.2f}% |\n")

        out.write(f"\n## Pipeline funnel (D = {D_M} m)\n\n")
        out.write(f"- certified: **{n_certified}**\n")
        out.write(f"- prefilter shortlist (numpy R² ≥ {PREFILTER_R2_FLOOR}, both axes): "
                   f"**{n_shortlist}**\n")
        out.write(f"- node-fit error rows (fit_batch.mjs, per-elem/axis): **{n_error}**\n")
        out.write(f"- final survivors (node-fit R² ≥ {NODE_R2_FLOOR}, both axes): "
                   f"**{len(survivors)}**\n\n")

        out.write("## Rayleigh-unseparable pairs observed (fitTides' own `unseparable`, "
                   "authoritative)\n\n")
        if unseparable_seen:
            out.write(", ".join(unseparable_seen) + "\n\n")
        else:
            out.write("(none reported)\n\n")

        out.write("## Sanity anchor — Seymour Narrows / Dodd Narrows\n\n")
        for slug, info in seymour_dodd.items():
            out.write(f"- **{slug}**: verdict {info['verdict']} "
                       f"(speed_med {info['speed_med']:.2f} kn) -> "
                       f"neighbourhood elements within {D_M} m graded "
                       f"**{info['status']}**\n")
        out.write("\n")
    print(open(path).read())


# ---------------------------------------------------------------------- --

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", default="data")
    ap.add_argument("--pilot", type=int, default=0,
                     help="if >0, run stage 3 over only this many shortlisted elements "
                          "(pilot timing run per task-4-brief.md's timebox)")
    args = ap.parse_args()
    data_dir = args.data_dir

    print("stage 1: certify (station_verdicts + grade_elements)...")
    mesh, elements, stations, statuses_by_d, counts_by_d = stage1_certify(data_dir)
    certified_positions = [i for i, st in enumerate(statuses_by_d[D_M]) if st == "yes"]
    print(f"  certified (D={D_M}): {len(certified_positions)} of {len(elements)} elements")
    for D in SENSITIVITY_D_M:
        c = counts_by_d[D]
        print(f"  D={D}: yes={c['yes']} masked={c['masked']} none={c['none']}")

    print(f"stage 2: numpy prefilter over {len(certified_positions)} certified elements...")
    t, u_kn, v_kn, shortlist_mask = stage2_prefilter(data_dir, certified_positions)
    shortlist_positions = [certified_positions[i] for i in range(len(certified_positions)) if shortlist_mask[i]]
    shortlist_elems = [elements[p]["i"] for p in shortlist_positions]
    shortlist_cols = list(range(len(certified_positions)))  # cols into u_kn/v_kn line up with certified_positions
    shortlist_cols = [c for c, keep in zip(shortlist_cols, shortlist_mask) if keep]
    n_shortlist_total = len(shortlist_elems)
    print(f"  shortlist (prefilter R² ≥ {PREFILTER_R2_FLOOR}): {n_shortlist_total} elements")

    if args.pilot:
        shortlist_elems = shortlist_elems[:args.pilot]
        shortlist_cols = shortlist_cols[:args.pilot]
        print(f"  --pilot {args.pilot}: restricting stage 3 to the first {len(shortlist_elems)} elements")

    fits_path = os.path.join(data_dir, "fits", "fits.jsonl")
    print("stage 3: streaming shortlist through fit_batch.mjs...")
    stage3_node_fits(shortlist_elems, shortlist_cols, t, u_kn, v_kn, fits_path)

    print("stage 4: computing final R² from node fits, applying floor...")
    survivors, n_error, unseparable_seen = build_survivors(
        fits_path, shortlist_elems, shortlist_cols, t, u_kn, v_kn)
    print(f"  survivors (node-fit R² ≥ {NODE_R2_FLOOR}, both axes): {len(survivors)}")

    survivors_path = os.path.join(data_dir, "survivors.json")
    write_survivors_json(survivors_path, survivors, counts_by_d)
    print(f"  wrote {survivors_path}")

    seymour_dodd = {}
    st_by_slug = {s["slug"]: s for s in stations}
    for slug in ("seymour-narrows", "dodd-narrows"):
        s = st_by_slug.get(slug)
        if not s:
            continue
        seymour_dodd[slug] = {
            "verdict": s["verdict"],
            "speed_med": s["speed_med"] if s["speed_med"] is not None else float("nan"),
            "status": _neighbourhood_status(elements, statuses_by_d[D_M], s),
        }

    report_path = os.path.join(data_dir, "SURVIVORS.md")
    write_report(report_path, stations, counts_by_d, len(certified_positions),
                 n_shortlist_total, survivors, n_error, unseparable_seen, seymour_dodd)
    print(f"wrote {report_path}")


def _neighbourhood_status(elements, statuses, station):
    """The grading status of the mesh element nearest this station (flat-
    earth, matching certify.grade_elements' own metric) -- used only for
    the SURVIVORS.md sanity-anchor line, not for grading itself."""
    M_PER_DEG_LAT = 111320.0
    import math
    lat0 = station["lat"]
    cos_lat = math.cos(math.radians(lat0))
    best_d, best_i = None, None
    for i, e in enumerate(elements):
        dx = (e["lon"] - station["lon"]) * M_PER_DEG_LAT * cos_lat
        dy = (e["lat"] - lat0) * M_PER_DEG_LAT
        d = math.hypot(dx, dy)
        if best_d is None or d < best_d:
            best_d, best_i = d, i
    return statuses[best_i]


if __name__ == "__main__":
    main()
