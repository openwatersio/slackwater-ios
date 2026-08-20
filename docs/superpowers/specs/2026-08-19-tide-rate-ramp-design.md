# Colouring the tide track by rate of rise

Issue: [#95](https://github.com/openwatersio/slackwater-ios/issues/95). The tide half of
the decision #97 opened; the current half shipped in
[2026-08-15-current-speed-ramp-design.md](2026-08-15-current-speed-ramp-design.md).
The decisions themselves were made in #95's comments — this doc records what shipped
and the numbers behind the domain.

## What was decided (in #95)

- **Tides encode rate of rise, not range.** Range is the headline number, but what
  strands someone on a flat is how fast the water arrives — the derivative, which is
  also the slope of the line already drawn.
- **The tide fill's colour channel was free.** Unlike the current track, the tide fill
  carried no direction semantic — a fixed decorative gradient (`#9CC0DC → #0D3A5C`),
  constant at every station and phase. The ramp displaces decoration, not meaning.
- **The extreme dots keep `SN.floodLabel`/`SN.ebbLabel`.** Peak rate falls at mid-tide,
  between the turns; the two encodings light up in complementary places.
- **No green.** Confirmed by @clarkbw on #95: green keeps its single meaning of
  transitable water, on the current track only. A "low rate" band on a tide chart would
  read as "safe to be out here", which depends on geography the app doesn't know.
- **Analytic derivative.** slackwater-engine v0.4.0 exposes
  `Station.rates(from:to:step:)` — the same `evalHPrime` its extremes bisection always
  used — on the same floored timeline as `heights`, so `tidePoints[i]` and
  `tideRates[i]` share a timestamp. No sample differencing (see `cardState`'s note on
  numerical noise near turns).

## The domain

```
tideRateAnchorsMHr = [0.15, 0.6, 1.5, 3.6]   // m/hr at t = 0, 1/3, 2/3, 1
                    ≈ 0.5,  2,   5,   12     // ft/hr
```

Same construction as the speed ramp: capability anchors, equally spaced,
piecewise-linear, clamped, hard-coded, never derived from on-device stations.

| Anchor | Meaning |
|---|---|
| 0.15 m/hr | standing water; a neap harbour tide |
| 0.6 m/hr | an ordinary coastal mid-tide |
| 1.5 m/hr | an inch a minute — a flat floods faster than the walk back off it |
| 3.6 m/hr | the Severn/Fundy regime; Avonmouth peaks 13.7 ft/hr |

Grounding, from `tools/ramp-domain.mjs` (analytic peak |dh/dt| over a synthesized year,
all 2,765 bundled stations, run 2026-08-19):

```
p50=1.50  p75=2.97  p90=4.59  p95=5.90  p99=8.13  max=13.89   (ft/hr)
fastest: 13.9 Port Isaac, 13.7 Avonmouth, 13.1 Saint Malo, 12.7 Newport
```

This domain lands the median at 22% of the ramp and p90 at 63% — the same spine the
speed ramp keeps (23%/56%). #95's Ile Haute estimate (~8 ft/hr) predated world
coverage; the Bristol Channel outruns it, so the ceiling sits at 12 ft/hr, not 8.
Cook Inlet's fast gauges are moot for the bundle — the datum gate dropped them
(`docs/validation/world-tide-stations.md`) — but a CHS-fitted Fundy station rides the
same ramp the day its fit lands, because a fitted station renders through the same
record/engine path as a bundled one.

The middle two anchors are estimates and want a source, same flag as the speed ramp's.

Known blur in the grounding numbers: `ramp-domain.mjs` still omits 3.18% of total
amplitude (world coverage added constituents its `SPEED` table lacks — `LAMBDA2` is
the largest, present in the table as `LAM2`), and its header still claims 0.71%.
Percentiles are order-of-magnitude robust to this; worth a table fix if the tool is
touched again.

## No schematic case

The current ramp needed `speedsAreSchematic` for derived gates. Tides have no
equivalent: every tide series on the strip comes from real constituents — bundled, or
CHS-fitted before the detail view ever renders. `tideFillStops` therefore has no
schematic parameter.

## Tests

- `testTideRampTLandsTheAnchorsWhereTheyBelong`, `testTideRampSpreadsOrdinaryStationsAcrossTheRamp` — the domain.
- `testTwoTidesOfDifferentSizeCannotFillTheSameColour` — the defect itself: an M2
  harbour tide and an M2 Fundy-scale tide produce different fill stops, the big one
  brighter. Engine-real series, not synthesized stops.
- Ramp colour properties (luminance monotonic, no green, ink contrast) are #97's tests,
  unchanged — the tide ramp reuses `SN.speedColour` wholesale.
