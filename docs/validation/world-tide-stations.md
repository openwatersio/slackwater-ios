# World tide stations — datum validation (2026-08-16)

This is the follow-on to `spikes/chs-currents-fit/README.md`'s method for the tide side
of world coverage: Task 6 of the world-tide-stations plan took Slackwater from 1,473
US+Canada tide stations to 2,765 worldwide by adding TICON reference stations outside
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

This is the method's own noise floor on data already known correct — a few centimetres,
not the tens of centimetres the tolerance below allows. That gap is what licenses the
tolerance; the exact multiple is worked out in the next section.

## The bar, stated before the results

**0.30 m.** The independent justification rests on the control alone, and needs no
knowledge of how any other group scores: the NOAA control measures 0.011 m median /
0.018 m max noise floor for this method on data already known to be correct, so 0.30 m
sits 16.7× the max and 27.3× the median above that floor (0.30 / 0.018, 0.30 / 0.011).
The gate fires only on deviations far larger than anything the check reports against data
we already trust.

**Provenance, stated plainly, because it isn't independent history.** 0.30 m was not
chosen blind. It was set during planning, in `task-2-brief.md`, written before Task 2
ever ran — but by someone who had already measured the UK and European distributions
this report presents, and `DATUM_TOLERANCE_M`'s own code comment justifies the number by
exactly those outcomes (it clears 97% of UK home waters and 99% of non-UK Europe while
still failing Southampton and Penarth). That is calibrated-with-knowledge, not a bar set
blind and scored afterward — the anti-pattern this document exists to catch, one level up
its own provenance chain. The control argument above is offered instead of, not
alongside, an appeal to how well 0.30 m happens to score against the groups below,
because that appeal is exactly the thing a reader can no longer trust as independent.

A station that fails is excluded from the shipped bundle (`gen-tides.mjs`, not touched by
this task); a station with no publishable `MHW`/`MLW` is `null` and ships un-gated, since
there is nothing to check it against.

PASS = `datumDeviation(station) <= 0.30` m. FAIL = exceeds it. UNJUDGEABLE (`null`) =
no published `MHW`/`MLW`, or no usable constituents — not counted as failing.

## Results by group

Measured 2026-08-16/17 against the committed `@neaps/tide-database` package (no network;
constituents and datums as published by each station's own authority). Every row is
measured over the **eligible pool** — `license.commercial_use === true`,
`type === "reference"`, `harmonic_constituents` has at least one non-zero amplitude, and
both `datums.MHW` and `datums.MLW` are defined (the filter the shipping test in
`datum-check.test.mjs` uses) — applied to `allStations` directly, **before**
`gen-tides.mjs`'s dedup/CHS-gating drops anything. A pass rate computed after that gate
would be meaningless: failures are already gone by the time a station reaches
`stations.json`, so a post-gate pass rate is 100% by construction regardless of how good
the check is.

| Group | n | median | p90 | max | pass rate |
|---|---|---|---|---|---|
| NOAA control | 25 | 0.011 m | 0.017 m | 0.018 m | 100% |
| Americas non-NOAA (eligible) | 2,537 | 0.032 m | 0.110 m | 0.725 m | 98.9% |
| UK home waters (lat 49–61°N) | 68 | 0.026 m | 0.085 m | 0.591 m | 97% |
| Europe non-UK | 744 | 0.024 m | 0.114 m | 1.313 m | 99% |
| Asia | 399 | 0.025 m | 0.094 m | 0.445 m | 99% |
| Oceania | 313 | 0.021 m | 0.101 m | 2.193 m | 99% |
| Africa | 81 | 0.018 m | 0.053 m | 0.127 m | 100% |

**Americas non-NOAA (eligible)** — `continent === "Americas"` and `id` does not start
with `noaa/` — is the single largest group measured in this report: 2,537 stations, more
than Europe, Asia, Oceania and Africa combined. It is the last continent-scale slice
`gen-tides.mjs` ships under this gate that this report hadn't yet measured. (This is a
distinct population from any "source is NOAA by name" reading that also sweeps in TICON
rows mirroring NOAA gauges — the `-usa-noaa`-suffixed ids — which is not what this row
counts; see the working notes for the trap in conflating the two.)

Asia, Oceania and Africa together account for 793 checkable stations (399 + 313 + 81)
outside NOAA/Americas-non-NOAA/UK/Europe that `gen-tides.mjs` ships under this same global gate
(`passesDatumCheck` is applied without a region carve-out). None of the six non-control
groups reads materially worse than any other — medians cluster 0.018–0.032 m, p90s
0.053–0.114 m, and every pass rate lands 97–100%. Oceania's max (2.193 m, one station) is
the largest single deviation measured in this report, well past the 0.30 m gate — meaning
that station does not ship; it is not evidence the group as a whole is weaker, since
Oceania's median and p90 are in line with everyone else.

**This is the report's most useful conclusion, not just its most reassuring one: the gate
behaves consistently worldwide, not just where we happened to look first.** North America
(the control), the Americas' non-NOAA majority, the UK, the rest of Europe, Asia, Oceania
and Africa all cluster in the same narrow band. The method doesn't quietly get worse the
farther a station sits from where it was first validated.

**On the 0.30 m vs. a tighter bar (Europe non-UK, re-measured):** at 0.15 m, 5.65% of all
744 checkable Europe non-UK stations fail outright, and 4.75% of the 737 that currently
pass at 0.30 m would newly fail. (The `tools/datum-check.mjs` comment previously quoted
"roughly 7%" for this; that number did not reproduce and has been corrected in the source
to match the measurement above.)

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

## What the gate removed from existing coverage

The section above names the two UK stations the gate refused to *add*. It says nothing
about what it *took away*, and that is the more important number for anyone already using
the app: **the gate removed 10 stations that were shipping before this branch, every one
of them in the United States.** Measured against the pre-branch bundle (`git diff` of
`Slackwater/Resources/stations.json`, same `@neaps/tide-database` 0.9.20260801 either
way), not inferred.

| Station | Deviation | Region | Nearest surviving station |
|---|---|---|---|
| Goose Creek | 0.675 m | Knik Arm · Cook Inlet, AK | North Foreland, 80.5 km |
| Carrollton | 0.521 m | New Orleans, LA | New Canal USCG station, 10.7 km |
| Ashland Ave | 0.385 m | Niagara Falls, NY | American Falls, 2.1 km |
| Port MacKenzie | 0.378 m | Anchorage, AK | North Foreland, 71.4 km |
| Point Possession | 0.366 m | Cook Inlet, AK | North Foreland, 40.4 km |
| Levelock | 0.329 m | Kvichak Bay, AK | Naknek, 43.3 km |
| Snag Point | 0.322 m | Dillingham, AK | Nushagak Bay (Clarks Point), 22.2 km |
| Anchorage | 0.308 m | Knik Arm, AK | North Foreland, 71.6 km |
| Grosse Pointe YC | 0.308 m | Grosse Pointe Shores, MI | St Clair Shores, 4.3 km |
| Fire Island | 0.304 m | Cook Inlet, AK | North Foreland, 53.0 km |

Seven of the ten are Alaskan, and **Upper Cook Inlet loses five of its six gauges** —
everything north of 61°N except North Foreland. That is defensible engineering rather
than an accident: Upper Cook Inlet has ~9 m of range and extreme shallow-water
distortion, which is precisely the water where a linear harmonic model is worst and
where this check is doing the job it was built for. Anchorage's own model carries 120
constituents — NOAA does not publish 120 anywhere the tide is simple.

**But the reader should see the cost of 0.30 over 0.35.** Three of the ten sit within 3%
of the bar (Anchorage and Grosse Pointe at 0.308, Fire Island at 0.304), and five of the
ten would survive a 0.35 m tolerance. The tolerance is justified by the NOAA control's
noise floor, and that argument is sound; it is not the same as saying the five stations
between 0.30 and 0.35 are unusable. It says we cannot vouch for them, and this branch
chose silence over an unvouched number.

**Anchorage is the one that took a fix, not just a measurement.** The gate ran before the
dedupe, so dropping `noaa/9455920` also stopped it blocking `ticon/anchorage-9455920-usa-noaa`
— a 50-constituent TICON refit of the *same gauge*, 0.0 km away, which then shipped in
its place. Its better-looking 0.237 m is scored against TICON's own recomputed datums,
which drift 0.2–0.4 m off an adopted chart datum (see `CHS_COVERAGE_KM` in
`gen-tides.mjs` — the CHS cede rule exists for exactly this, and nothing protected US
water). A gate-failing NOAA row now still claims its position in the dedupe grid and then
leaves, so Anchorage yields **no** station. "We cannot vouch for this water" has to mean
no pin, not a worse pin.

### The other 14 stations this branch stopped shipping

Not the gate — deduplication, and all of them redundant rather than lost. Every one is a
second publisher's copy of a gauge that still ships under a NOAA or curated name
(Charlotte Amalie, Guantanamo Bay, Hilo, Kodiak, Mona Island, Nawiliwili, Neah Bay, New
London, Ocean Springs, Palmyra Island, Panama City, Port San Luis, Prudhoe Bay, Sault Ste
Marie — each within 0.0–4.3 km of its survivor, all scoring under 0.12 m). The nearest
survivor is listed for every one of the 24 in the branch's final-fix report.

### Stations the gate could not judge at all

`passesDatumCheck` returns `true` when `datumDeviation` is `null` — an unjudgeable station
is not a failing one (see The method, above). **15 shipped stations take that path**,
publishing no `MHW`/`MLW`: Apia (Observatory), Balboa, Cristobal (Colon), Djakarta,
Eugene Island, Fort Wadsworth, Guayaquil, Guaymas, La Libertad, La Union (Cutuco),
Malakal Harbor, Massacre Bay, Puntarenas, Salina Cruz and San Cristobal. Twelve are new
on this branch; three (Eugene Island, Fort Wadsworth, Massacre Bay) were already
shipping. Every results table in this report excludes them by construction, so no pass
rate quoted anywhere here covers them.

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

The datum/amplitude gate passes at 97–100% across all seven measured groups (NOAA
control, Americas non-NOAA, UK home waters, Europe non-UK, Asia, Oceania, Africa), its
control's noise floor sits 16.7–27.3× below its tolerance, and its two named failures are
explained and excluded rather than shipped quietly. The consistency across groups matters
as much as any single number: the gate performs the same everywhere it was checked, not
just on the water it was built and calibrated against. That is enough to justify shipping
the passing stations'
levels under a trusted name. It is not, on its own, enough to claim their timing is
validated — that claim is not made here.
