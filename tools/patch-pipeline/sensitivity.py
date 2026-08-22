#!/usr/bin/env -S uv run --script --with numpy,rasterio
"""Slackwater patch-pipeline — cross-section sensitivity sweep (spec §6b.2).

Variants: sections shifted +/- half a spacing along the thalweg seed; datum
at chart datum (cd_to_mwl_m = 0) instead of MWL. Any section whose spring-peak
speed (scale x anchor spring_max_kn) moves more than max(10%, 0.25 kn) under
any variant is dropped; kept_range = longest contiguous stable run containing
the anchor, WITHIN the committed (flare-truncated) kept_range already on the
pass -- sensitivity truncation composes with the flare rule, it never widens
past it. The committed pass artifact is updated in place -- shrink, never
smooth.
"""
import json, math, sys
from sections import M_PER_DEG_LAT, _m_per_deg_lon, build_pass, tile_depth_fn


def kept_range_from_deltas(base_scales, variant_scales, anchor, spring_max_kn, within=None):
    if within is None:
        within = [0, len(base_scales) - 1]
    wlo, whi = within
    keep = []
    for i, s in enumerate(base_scales):
        bar = max(0.10 * s * spring_max_kn, 0.25)
        ok = all(i < len(v) and v[i] is not None and abs(v[i] - s) * spring_max_kn <= bar
                for v in variant_scales)
        keep.append(ok)
    if not keep[anchor]:
        raise SystemExit("anchor section is sensitivity-unstable — bad tiles or bad anchor placement")
    lo = anchor
    while lo > wlo and keep[lo - 1]:
        lo -= 1
    hi = anchor
    while hi < whi and keep[hi + 1]:
        hi += 1
    return [lo, hi]


def align_to_anchor(base_len, base_anchor, variant_scales, variant_anchor):
    """Reindex variant_scales so position i means "the same physical section
    as base index i", using the anchor as the one point both runs are known
    to agree on (each build_pass recomputes its own anchor independently, by
    nearest-section-to-the-real-world-anchor-coordinate). A seed-start shift
    re-phases the whole downstream walk, which can add or drop a station
    upstream of the anchor -- so raw index i in a variant is not reliably the
    same station as index i in the base; base_index + (variant_anchor -
    base_anchor) is. Returns a list of length base_len; positions with no
    corresponding variant station are None (kept_range_from_deltas treats
    that as unverifiable -> unstable, same as running off the end of a
    same-length list)."""
    offset = variant_anchor - base_anchor
    n = len(variant_scales)
    return [variant_scales[i + offset] if 0 <= i + offset < n else None
            for i in range(base_len)]


def variant(inputs, depth_at, shift_frac=0.0, cd_override=None):
    v = dict(inputs)
    if cd_override is not None:
        v = dict(v, cd_to_mwl_m=cd_override)
    if shift_frac:
        # shift the seed start point along the first seed segment by
        # shift_frac * section_spacing_m (metres) -- cheap re-jitter of every
        # downstream station position. NOTE: the brief's own formula moved
        # seed[0] by shift_frac of the *segment length*, not of a spacing;
        # the hand-drawn seed's first segment runs several spacings long
        # (2.4x for deception-pass, 3.6x for tacoma-narrows), so that
        # produced a multi-spacing perturbation -- enough to shift the whole
        # downstream station numbering by a full index and misalign every
        # subsequent by-index comparison. This computes the true half-spacing
        # offset the docstring (and the task brief prose) describes.
        seed = [list(p) for p in v["thalweg_seed"]]
        p0, p1 = seed[0], seed[1]
        dx = (p1[0] - p0[0]) * _m_per_deg_lon(p0[1])
        dy = (p1[1] - p0[1]) * M_PER_DEG_LAT
        seg_m = math.hypot(dx, dy)
        f = (shift_frac * v["section_spacing_m"]) / seg_m if seg_m else 0.0
        seed[0] = [p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f]
        v = dict(v, thalweg_seed=seed)
    return build_pass(v, depth_at)


def main(slug):
    inputs = json.load(open(f"inputs/{slug}.json"))
    doc = json.load(open(f"passes/{slug}.json"))
    depth_mwl = tile_depth_fn(f"data/tiles/{slug}", inputs["tile_value"], inputs["cd_to_mwl_m"])
    depth_cd = tile_depth_fn(f"data/tiles/{slug}", inputs["tile_value"], 0.0)
    variants = [
        variant(inputs, depth_mwl, shift_frac=+0.5),
        variant(inputs, depth_mwl, shift_frac=-0.5),
        variant(inputs, depth_cd, cd_override=0.0),
    ]
    # align each variant to the base by anchor position, not raw index —
    # variant runs may differ in count upstream of the anchor
    base_anchor = doc["anchor"]["section_index"]
    vscales = [align_to_anchor(len(doc["scales"]), base_anchor, v["scales"], v["anchor"]["section_index"])
              for v in variants]
    before = doc["kept_range"]  # already flare-truncated (sections.py); sensitivity narrows further
    kr = kept_range_from_deltas(doc["scales"], vscales,
                                base_anchor,
                                doc["anchor"]["spring_max_kn"],
                                within=before)
    doc["kept_range"] = kr
    doc["sensitivity"] = {"variants": ["shift+0.5", "shift-0.5", "datum=CD"],
                          "kept_range_before": before,
                          "dropped_below": kr[0] - before[0],
                          "dropped_above": before[1] - kr[1]}
    json.dump(doc, open(f"passes/{slug}.json", "w"), indent=1)
    print(f"{slug}: kept sections {kr[0]}..{kr[1]} (was {before[0]}..{before[1]}) of 0..{len(doc['scales']) - 1}")


if __name__ == "__main__":
    main(sys.argv[1])
