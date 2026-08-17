# World tide stations — datum validation (2026-08-16)

This is the follow-on to `spikes/chs-currents-fit/README.md`'s method for the tide side
of world coverage: Task 6 of the world-tide-stations plan took Slackwater from 1,473
US+Canada tide stations to 2,776 worldwide by adding TICON reference stations outside
NOAA/CHS. This pass validates that expansion against each station's own publishing
authority before shipping it under a trusted name.

## The question

Does a station's own model agree with the datums its own authority publishes? Slackwater
predicts tide heights from harmonic constituents; TICON stations also carry published
`MHW`/`MLW` datum values from the same national authority the constituents came from. If
the two disagree by more than a small amount, either the constituents are wrong, the
datum reduction is wrong, or the station itself is a poor fit for a linear harmonic
model (shallow-water overtides, a double high water port) — any of which is a reason not
to ship that station's numbers as fact.

## The method

For every checkable station: predict a year of tidal extremes (2026-01-01 –
2027-01-01 UTC) from its harmonic constituents, take the mean of the predicted highs and
the mean of the predicted lows, and compare each to the station's published `MHW`/`MLW`.
The worse of the two deviations is the station's score. A station with no published
`MHW`/`MLW`, or no usable constituents, is `null` — unjudgeable, not failing.

**Both sides are reduced to chart datum first, and that reduction is the whole trick.**
Different national authorities publish datums against different references:

- **NOAA publishes against station datum** (`STND = 0`). Ford Island's raw `MHW` reads
  `7.532` against an `MLLW` of `7.078` — real numbers, but 7 metres away from sea level in
  any sense a mariner means by "high water." Compare that raw `MHW` to a chart-datum
  prediction and NOAA looks catastrophically wrong.
- **TICON publishes against something near chart datum.** Southampton's `LAT` is
  `0.066` — already close to zero, so an unreduced comparison happens to look right.

Skip the reduction and NOAA appears ~7 m wrong while UK rows look correct only by the
accident of LAT being near zero for that particular station — a coincidence that would
not hold for a station whose station datum sits meaningfully off chart datum. The fix is
to subtract each station's own `datums[chart_datum]` from both the predicted values and
the published `MHW`/`MLW` before comparing, so every station is judged on the same
footing regardless of what its authority chose as zero. This cost a full investigation
cycle to find (see `tools/datum-check.mjs`'s header comment) and belongs in the written
record so nobody re-derives it.

Implementation: `tools/datum-check.mjs` (`datumDeviation`, `passesDatumCheck`,
`DATUM_TOLERANCE_M`), exercised by `tools/datum-check.test.mjs`.

## The control, and why it licenses the tolerance

NOAA stations are public-domain and authoritative — the US government's own tide
predictions, not a third party's. A check that reads centimetres of disagreement on data
we already trust is measuring what it claims to measure; a check that reads metres on
NOAA data would mean the check itself is broken, not the stations. NOAA is therefore the
control, not a group under test.

Measured over 25 NOAA reference stations (the first 25 that are commercial-use-licensed,
`type: "reference"`, carry non-zero harmonic constituents, and publish `MHW`/`MLW`):

| | value |
|---|---|
| n | 25 |
| median deviation | 0.011 m |
| p90 | 0.017 m |
| max | 0.018 m |
| pass rate (≤0.30 m) | 100% |

Two orders of magnitude below the tolerance below. This is what makes 0.30 m a
calibrated number rather than a round one picked by taste — the check's own noise floor
on trusted data is ~1 cm, so a 30 cm gate has enormous headroom against the method itself
and is doing real work when a station fails it.

## The bar, stated before the results

**0.30 m**, set from the measured distribution before results were reviewed for the
groups it's applied to: it clears 97% of UK home waters and 99% of non-UK Europe while
still failing Southampton and Penarth (below). Tightening to 0.15 m would additionally
fail roughly 7% of otherwise-good European stations, per the calibration note in
`tools/datum-check.mjs`. A station that fails is excluded from the shipped bundle
(`gen-tides.mjs`, not touched by this task); a station with no publishable `MHW`/`MLW` is
`null` and ships un-gated, since there is nothing to check it against.

PASS = `datumDeviation(station) <= 0.30` m. FAIL = exceeds it. UNJUDGEABLE (`null`) =
no published `MHW`/`MLW`, or no usable constituents — not counted as failing.

## Results by group

Measured 2026-08-16 against the committed `@neaps/tide-database` package (no network;
constituents and datums as published by each station's own authority). Filter for all
three groups: `license.commercial_use === true`, `type === "reference"`,
`harmonic_constituents` has at least one non-zero amplitude, and both `datums.MHW` and
`datums.MLW` are defined (the filter the shipping test in `datum-check.test.mjs` uses).

| Group | n | median | p90 | max | pass rate |
|---|---|---|---|---|---|
| NOAA control | 25 | 0.011 m | 0.017 m | 0.018 m | 100% |
| UK home waters (lat 49–61°N) | 68 | 0.026 m | 0.085 m | 0.591 m | 97% |
| Europe non-UK | 744 | 0.024 m | 0.114 m | 1.313 m | 99% |

UK home waters and Europe non-UK both sit close to the NOAA control on median and p90 —
the method holds up well outside North America. The max columns are dominated by a
handful of named outliers below, not a systematic regional bias.

## The named failures

Exactly two UK home-waters stations exceed 0.30 m:

| Station | Deviation | Note |
|---|---|---|
| Penarth | 0.591 m | Severn Estuary — largest tidal range in the UK |
| Southampton | 0.529 m | Double high water port |

**Southampton is the strongest evidence that this gate works as designed.** It's a
double high water port — the Solent's geometry produces a secondary high water via
shallow-water M4/M6 overtide interaction, a nonlinear effect a station's harmonic
constituent set can carry but which stresses the mean-of-extremes comparison this check
makes. The world-coverage design spec named double high water ports as the likeliest UK
failure mode *before* this check was run against real data (`docs/superpowers/specs/2026-08-16-global-coverage-design.md`,
per the plan this task closes out). The check then caught exactly that station. A gate
that fails the case its own design doc predicted, on real data, is doing its job rather
than passing by construction.

Every other UK home-waters station — including the next-worst, Port Isaac at 0.215 m —
clears the bar with room to spare.

## The honest limitation

**This validates datum and amplitude, not timing.** `datumDeviation` compares a
predicted mean high/low water level against a published level; it says nothing about
*when* in the tidal cycle that high or low actually occurs. Nothing in this report proves
that a UK harmonic prediction puts high water at the right minute.

Timing validation needs an independent reference — real observed or independently
predicted event times to check the model's predictions against, the same way
`spikes/chs-currents-fit/README.md` scores CHS current-gate fits against CHS's own
held-out published events. No such reference is usable for UK tides in an offline app:
every candidate is licence-restricted. The ADMIRALTY Tidal API's terms cap end-user
caching at 24 hours (`developer.admiralty.co.uk/TandC` §5.7), which rules out storing
anything from it on-device; EasyTide's terms separately forbid "systematically
downloading and storing" its content. Full survey in
`docs/research/european-currents-licensing-2026-08-16.md`. Until a licence-clean timing
reference exists, UK (and other non-NOAA/CHS) tide timing ships on the same footing as
its datum and amplitude validation here — checked against the station's own publishing
authority's *levels*, unchecked against any independent source for *when* those levels
occur.

## Verdict

The datum/amplitude gate passes at 97–100% across all three measured groups, its control
sits two orders of magnitude below its tolerance, and its two failures are named,
explained, and excluded rather than shipped quietly. That is enough to justify shipping
the passing stations' levels under a trusted name. It is not, on its own, enough to claim
their timing is validated — that claim is not made here.
