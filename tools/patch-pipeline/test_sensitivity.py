# tools/patch-pipeline/test_sensitivity.py — uv run --with pytest,numpy pytest -q test_sensitivity.py
from sensitivity import align_to_anchor, check_anchor_stability, kept_range_from_deltas


def test_stable_everywhere_keeps_all():
    base = [1.0, 1.1, 1.3, 1.6]           # scales
    variants = [[1.0, 1.12, 1.31, 1.62]]  # small deltas
    assert kept_range_from_deltas(base, variants, anchor=0, spring_max_kn=4.0) == [0, 3]


def test_unstable_tail_truncated():
    base = [1.0, 1.1, 1.3, 3.0]
    variants = [[1.0, 1.1, 1.3, 5.0]]     # last section swings 8 kn at springs
    assert kept_range_from_deltas(base, variants, anchor=0, spring_max_kn=4.0) == [0, 2]


def test_range_must_contain_anchor():
    base = [3.0, 1.0, 1.1]
    variants = [[5.0, 1.0, 1.1]]          # unstable section 0 = the anchor itself
    try:
        kept_range_from_deltas(base, variants, anchor=0, spring_max_kn=4.0)
        assert False, "anchor section unstable must be a hard error"
    except SystemExit:
        pass


def test_within_narrows_a_stable_run():
    # sensitivity truncation composes WITH the flare truncation: even though
    # every section here is stable, `within` (the committed, flare-truncated
    # kept_range) caps the walk -- the result must never widen past it.
    base = [1.0, 1.05, 1.1, 1.15, 1.2]
    variants = [[1.0, 1.06, 1.11, 1.16, 1.21]]  # stable everywhere
    assert kept_range_from_deltas(base, variants, anchor=2, spring_max_kn=4.0,
                                  within=[1, 3]) == [1, 3]


def test_align_to_anchor_shifts_by_anchor_offset():
    # A variant whose own anchor landed one station later than the base's
    # (a seed-phase shift added a station upstream) must be reindexed so
    # base index i still reads the same physical section, not raw index i.
    variant_scales = [9.0, 8.0, 1.0, 1.2, 1.3]  # variant anchor at index 2
    aligned = align_to_anchor(base_len=4, base_anchor=1,
                              variant_scales=variant_scales, variant_anchor=2)
    assert aligned == [8.0, 1.0, 1.2, 1.3]


def test_align_to_anchor_marks_missing_overlap_as_none():
    variant_scales = [1.0, 1.1]  # variant anchor at index 0, only 1 station past it
    aligned = align_to_anchor(base_len=4, base_anchor=0,
                              variant_scales=variant_scales, variant_anchor=0)
    assert aligned == [1.0, 1.1, None, None]


# Regression: align_to_anchor pivots the comparison on each run's own anchor,
# and scale is self-normalized (== 1.0 at a run's own anchor by construction)
# -- so a scale-based anchor check is dead code forever once aligned. These
# exercise a real, non-self-normalized signal instead: absolute area at the
# anchor's physical position, plus the anchor's index drift.

def _variant(anchor_index, sections):
    return {"anchor": {"section_index": anchor_index}, "sections": sections}


def test_anchor_area_swing_hard_errors():
    # anchor doesn't drift (index 2 in both), but the physical area computed
    # there swings 40% -- real placement instability, must not be masked by
    # the self-normalized scale (which would show delta 0 at the anchor).
    variants = [_variant(2, [{"area_reach_m2": 50.0}, {"area_reach_m2": 80.0}, {"area_reach_m2": 140.0}])]
    try:
        check_anchor_stability(base_anchor=2, base_anchor_area=100.0,
                               variants=variants, labels=["shift+0.5"])
        assert False, "40% anchor area swing must be a hard error"
    except SystemExit:
        pass


def test_anchor_drift_hard_errors():
    # anchor's own nearest-section assignment moved 2 stations under a
    # half-spacing nudge -- unstable by definition, regardless of area match.
    variants = [_variant(4, [{"area_reach_m2": 0}, {"area_reach_m2": 0}, {"area_reach_m2": 0}, {"area_reach_m2": 0},
                             {"area_reach_m2": 100.0}])]
    try:
        check_anchor_stability(base_anchor=2, base_anchor_area=100.0,
                               variants=variants, labels=["shift-0.5"])
        assert False, "anchor drift of 2 stations must be a hard error"
    except SystemExit:
        pass


def test_anchor_stability_returns_evidence_when_stable():
    variants = [_variant(2, [{}, {}, {"area_reach_m2": 104.0}])]
    evidence = check_anchor_stability(base_anchor=2, base_anchor_area=100.0,
                                      variants=variants, labels=["datum=CD"])
    assert evidence == [{"label": "datum=CD", "anchor_index_offset": 0, "anchor_area_delta_pct": 4.0}]
