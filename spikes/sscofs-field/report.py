#!/usr/bin/env -S uv run --script
"""Aggregate results/*.json into RESULTS.md: per-station verdicts, element
coverage, the spec's three decision-gate verdicts, and the bundle-size
extrapolation.

results/<label>.json is fit-validation's own 210d report.json (copied in by
run_matrix.sh) — the window its own exit code reflects — so this reads
structured fields straight off disk instead of re-parsing stdout text.
"""
import glob, json, os

# Two truth stations never got a mesh element within 600 m, so make_samples.py
# never emitted samples for them and they never entered samples/index.json
# (see export.log: "gabriola-passage / tillicum-bridge: NO ELEMENT within
# 600 m — record as coverage gap"). Their absence from index.json *is* the
# evidence; nothing here re-derives it.
COVERAGE_GAPS = ["gabriola-passage", "tillicum-bridge"]

BUNDLE_BUDGET_MB = 40  # spec §3 gate 3


def parse(path):
    r = json.load(open(path))
    return {"slack_med": r["slackMedianMin"], "slack_max": r["slackMaxMin"],
            "ext_med": r["extremaMedianMin"], "speed_med": r["speedMedianKn"],
            "verdict": "PASS" if r["pass"] else "FAIL"}


def bundle_extrapolation(n_box_elements, box_deg2, k_constituents=(23, 12)):
    # Render region ~ Salish clip -125.5..-122.0 x 47.0..50.6 (the seamap bbox, #30).
    render_deg2 = (125.5 - 122.0) * (50.6 - 47.0)
    n_render = n_box_elements / box_deg2 * render_deg2   # density extrapolation
    rows = []
    for k in k_constituents:
        bytes_per = k * 2 * (1 + 2 + 2) + 8              # id + f16 amp + f16 phase, x(u,v), + header
        rows.append((k, n_render, n_render * bytes_per / 1e6))
    return rows


def main():
    idx = json.load(open("samples/index.json"))
    by_label = {f"{r['slug']}-e{r['elem']}": r for r in idx}
    total_pairs = len(idx)
    n_done = len(glob.glob("results/*.done"))

    per_station = {}
    for path in sorted(glob.glob("results/*.json")):
        label = os.path.basename(path)[:-5]
        if label not in by_label:
            continue
        per_station.setdefault(by_label[label]["slug"], []).append({**parse(path), **by_label[label]})
    n_scored = sum(len(rows) for rows in per_station.values())

    # speed_med == -1 is fit-validation's sentinel for "no scoreable extremum"
    # (main.swift: obs.speed skipped below SIGNIFICANT_KN = 0.75 kn) — not a
    # real error, and never a legitimate min(). Split it out per station before
    # any best/nearest selection or pass counting; a station where every row is
    # sentinel never had a scoreable element at all.
    scoreable = {}
    unscoreable = []
    for slug, rows in per_station.items():
        good = [r for r in rows if r["speed_med"] >= 0]
        if good:
            scoreable[slug] = good
        else:
            unscoreable.append(slug)

    els = json.load(open("mesh/elements.json"))
    box = els["box"]
    box_deg2 = (box[2] - box[0]) * (box[3] - box[1])
    bundle_rows = bundle_extrapolation(len(els["elements"]), box_deg2)

    with open("RESULTS.md", "w") as out:
        out.write("# SSCOFS field spike — results\n\n")
        out.write(f"Pairs run: {n_done} / {total_pairs} in samples/index.json "
                   f"({n_scored} produced a scoreable 210d report; the rest "
                   f"either haven't run yet or hit FAIL-FOR-FITTING).\n\n")

        out.write("## Per-station (best + nearest element)\n\n")
        out.write("| station | dist m | slack med | slack max | ext med | speed med | verdict |\n")
        out.write("|---|---|---|---|---|---|---|\n")
        for slug, rows in sorted(scoreable.items()):
            best = min(rows, key=lambda r: r["speed_med"])
            near = min(rows, key=lambda r: r["dist_m"])
            for tag, r in (("best", best), ("nearest", near)):
                out.write(f"| {slug} ({tag}, e{r['elem']}) | {r['dist_m']} | {r['slack_med']:.1f} | "
                          f"{r['slack_max']:.1f} | {r['ext_med']:.1f} | {r['speed_med']:.2f} | {r['verdict']} |\n")

        out.write("\n## Element coverage per station\n\n")
        out.write("| station | elements scored |\n|---|---|\n")
        for slug, rows in sorted(per_station.items()):
            out.write(f"| {slug} | {len(rows)} |\n")

        out.write("\n## Coverage gaps\n\n")
        out.write(f"{len(COVERAGE_GAPS)} truth stations had no mesh element within 600 m and so never "
                   f"reached samples/index.json (make_samples.py; see export.log): "
                   f"{', '.join(COVERAGE_GAPS)}.\n")

        out.write("\n## Unscoreable stations (all published extrema < 0.75 kn)\n\n")
        out.write(f"{len(unscoreable)} station(s) reached samples/index.json but every nearby element's "
                   f"published extrema fell below fit-validation's SIGNIFICANT_KN floor (0.75 kn), so "
                   f"speedMedianKn is fit-validation's -1 sentinel (no scoreable extremum) on every row — "
                   f"excluded from the best/nearest table and decision gate 1: "
                   f"{', '.join(sorted(unscoreable)) or '(none)'}.\n")

        out.write("\n## Decision gates (spec §3)\n\n")
        passing = sorted(slug for slug, rows in scoreable.items()
                          if min(rows, key=lambda r: r["speed_med"])["verdict"] == "PASS")
        failing = sorted(slug for slug, rows in scoreable.items()
                          if min(rows, key=lambda r: r["speed_med"])["verdict"] == "FAIL")
        out.write(f"1. **Certifiable sub-regions meet the bar:** {len(passing)}/{len(scoreable)} scoreable "
                   f"stations PASS on their best element — {', '.join(passing) or '(none)'}. "
                   f"Failing: {', '.join(failing) or '(none)'}.\n")
        dodd = {slug: rows for slug, rows in per_station.items() if "dodd" in slug}
        if dodd:
            dodd_verdicts = {slug: [r["verdict"] for r in rows] for slug, rows in dodd.items()}
            all_fail = all(v == "FAIL" for vs in dodd_verdicts.values() for v in vs)
            out.write(f"2. **Dodd-class stations correctly fail:** {dodd_verdicts} — "
                       f"{'all FAIL as expected' if all_fail else 'UNEXPECTED PASS — investigate before trusting anything else'}.\n")
        else:
            out.write("2. **Dodd-class stations correctly fail:** no dodd-* pair in this results set.\n")
        under_budget = [k for k, _, mb in bundle_rows if mb <= BUNDLE_BUDGET_MB]
        out.write(f"3. **Bundle ≤ {BUNDLE_BUDGET_MB} MB:** " +
                   (f"k = {min(under_budget)} constituents fits" if under_budget
                    else f"no evaluated constituent count fits") + ".\n")

        out.write("\n## Bundle extrapolation\n\n")
        for k, n, mb in bundle_rows:
            out.write(f"- {k} constituents: ~{n:,.0f} render-region elements → **{mb:.1f} MB**\n")
    print(open("RESULTS.md").read())


if __name__ == "__main__":
    main()
