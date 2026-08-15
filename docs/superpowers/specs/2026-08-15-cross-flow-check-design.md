# Cross-flow check — bounding the 1-D current projection at extract time

2026-08-15. Approved in brainstorm. Tracking issue: #104. Origin: #102, which
proposed bundling NOAA's tidal-ellipse parameters and was closed after
measurement — the minor axis is worth a median 4% of peak speed, and adopting a
2-D magnitude series would silently break slack detection (`findSlacks` in
slackwater-engine requires a scalar zero crossing; a 2-D magnitude never reaches
zero at 836 of 850 stations).

**The part of #102 that survived:** NOAA publishes enough to tell us where our
own 1-D major-axis model is a poor fit, and today nothing measures that. This
spec turns that into a build-time bound rather than a shipped feature.

## Decision

`@sailingnaturali/current-stations` records a **cross-flow census** in the
bundle it emits, and `validateBundle` asserts a bound on it. Nothing is added to
any per-station record, nothing new reaches a device, and no UI changes.

**Implementation lands entirely in `current-stations`.** This repo is the
consumer whose honesty question drove the work and where #104 is tracked, but
`slackwater-ios` gets no code in this change — see §5.

## §0 Why the obvious approach doesn't work

Recorded because it is the thing a reader will re-propose.

`data/noaa-currents.json` carries `{name, amplitude, phase}` per constituent
plus `floodDirection` / `ebbDirection` / `offset`, and **no minor-axis field of
any kind**. So a check inside `tools/gen-noaa-currents.mjs` is impossible
without an upstream change and a full re-extract. The extractor already holds
the complete harcon at `ensureHarmonic`, so upstream the data is free.

The measurement in #102 used a 60-day, 1-minute time-domain evaluation with the
Swift engine. **No closed form reproduces it well enough to classify stations** —
measured over all 841 bundled stations:

| candidate estimator | correlation vs measured residual |
|---|---|
| RMS cross-axis + \|Z₀ minor\| | 0.834 |
| quadrature-corrected RMS (`m·sin Δg`) | 0.838 |
| M2 ellipticity alone | 0.348 |

Correlation of 0.84 sounds adequate and is not: calibration spreads 1.0–2.7×
across stations, and at the matching threshold the best estimator produced 122
false positives against 64 true ones. The residual at slack is `|v|`
*conditioned on* `u = 0`, which depends on the full multi-constituent
superposition. **Asserting the true residual would require a harmonic evaluator
inside a package that is deliberately zero-dependency**, so this spec does not.

## §1 The quantity

**NOAA `minorMeanSpeed`** — the DC component of flow perpendicular to the flood
axis. Present at all times, including slack. Exactly known from the harcon, no
estimation, no evaluator.

It is not the residual-at-slack, and the spec does not claim it is. It is a
distinct, exactly-true statement — *there is a persistent cross-axis current
here* — which at the median station accounts for **82%** of the measured
residual.

Per harmonic record, over that record's own bin:

```
crossFlow     = |cons[0].minorMeanSpeed|            (knots)
alongAxisPeak = Σ|majorAmplitude| + |majorMeanSpeed| (knots)
ratio         = alongAxisPeak > 0 ? crossFlow / alongAxisPeak : 0
```

`cons[0]` matches the extractor's existing idiom for `azi` and `majorMeanSpeed`.
It is safe for `minorMeanSpeed` too, and this was verified rather than assumed:
**0 of 2,800 harmonic bin-records vary it across their constituents.**

## §2 The bound

**Relative, not absolute.** The failure being guarded against is "the flood axis
is a poor description of this station" — inherently a ratio. An absolute knot
bound only catches NOAA publishing something insane.

Measured across the 850 primary-bin type-H stations today:

| cross-flow ÷ along-axis peak | p50 | p90 | p99 | max |
|---|---|---|---|---|
| | 0.018 | 0.066 | 0.136 | **0.241** (`BOS1130`) |

Re-checked across **all 2,800 harmonic bin-records** — not just primary bins,
since the bundle carries `@bin` entries too — the worst ratio is unchanged at
0.241 (`BOS1130`). Worst absolute rises slightly, to 0.82 kn at `PUG1619@32`.

**Bound: `ratio ≤ 0.5`** — 2.08× headroom over today's worst across every
record the bundle contains. It rejects nothing now and is a regression guard,
which is the intent. No absolute knob is carried, because two knobs is one more
than the failure needs.

## §3 Where it lives

Three seams, each already established in the package.

**`src/extract.js`** — compute per-record cross-flow in `ensureHarmonic`, where
the harcon is in scope. Aggregate with a **pure function** (testable without
network) and record onto the bundle beside the existing `note` / `generated`:

```json
{
  "note": "Generated from NOAA CO-OPS mdapi …",
  "generated": "2026-08-15T…",
  "crossFlow": {
    "measured": "NOAA minorMeanSpeed — flow perpendicular to the flood axis, present at all times including slack",
    "records": 2800,
    "gte0_25kn": 170,
    "gte0_50kn": 24,
    "worstRatio": { "id": "BOS1130", "crossFlow": 0.18, "alongAxisPeak": 0.74, "ratio": 0.241 },
    "worstAbsolute": { "id": "PUG1619@32", "crossFlow": 0.82 }
  },
  "stations": [ … ]
}
```

~200 bytes of bundle metadata. **No per-station field.**

Counts cover **every harmonic record in the bundle**, `@bin` entries included —
2,800 records, not the 841 primary-bin stations `slackwater-ios` ends up
shipping. The figures above are today's measured values and are what a first
extract should reproduce; treat a material divergence as a finding, not a
rounding difference.

**`src/validate.js`** — `validateBundle` asserts `worstRatio.ratio ≤ 0.5`. This
is the load-bearing reason the census is stored rather than printed: the check
then runs **offline, against any existing bundle, with no re-extract**.

**`bin/current-stations.mjs`** — print the census under `extract` and
`validate`; `process.exitCode = 1` on breach, matching the existing `validate`
and `check` commands.

A census that exists only in the scrollback of a run performed twice a year is
not a check. Storing it is what makes it one.

## §4 Testing

Against `test/validate.test.js`'s existing `harmonic()` fixture helper:

- ratio over bound → `ok: false`, offending station named in the error
- ratio under bound → `ok: true`
- **bundle with no `crossFlow` block → `ok: true`**, reported as "not measured"

The third is required, not optional: the currently vendored extract has no such
block, and older bundles must not go red on a check that postdates them.

Census aggregation is tested directly as a pure function over synthetic records —
no network.

Edge cases, all present in the real data:

| case | handling |
|---|---|
| `minorMeanSpeed` absent | treat as 0 — matches the existing `?? 0` idiom; 14 stations are purely rectilinear |
| `alongAxisPeak` == 0 | guard the divide, ratio 0 |
| subordinate stations | excluded — no harcon of their own |
| `@bin` records | included — genuine harmonic entries |

## §5 Sequencing — deliberately two changes

The census only populates on a re-extract (~2,800 paced requests, several
minutes). Therefore:

1. **This change:** `current-stations` only. Compute, store, validate, test,
   release. `slackwater-ios` untouched.
2. **Separately:** re-extract, re-vendor `data/noaa-currents.json`, and add the
   ~3-line re-assert to `tools/gen-noaa-currents.mjs` so `build:data` enforces
   the bound too — still shipping **zero** bytes to `Resources/currents.json`,
   which is written as a bare station array.

They are split because a re-extract is precisely the "did the vendored inputs
move?" event, and any station drift it surfaces deserves review on its own
merits rather than arriving mixed into a validation change. Splitting also
avoids landing a guard in `slackwater-ios` that is inert until the re-vendor.

#104 stays open after step 1, re-scoped to track step 2.

## §6 Non-goals

- No per-station field, no shipped bytes, no UI. (Settled in brainstorm: the
  consumer is a build-time honesty check, not the app.)
- No harmonic evaluator in `current-stations`; no residual-at-slack assertion.
- Nothing touching map rendering — #57 owns that and does not wait on this.
- #102 stays closed. This does not reopen bundling the minor axis.

## §7 Documentation to update in the same change

`docs/schema.md:100` and `docs/noaa-api.md:80` currently state that the
minor-axis fields are fetched and deliberately not carried. That stays true of
the per-station records and becomes incomplete at the bundle level — both need a
line pointing at the census and the bound.
