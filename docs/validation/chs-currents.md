# CHS current fit validation

This record supports the gate admission and provisional-fit rules in [the CHS data model](../chs-data-model.md#5-what-validated-means-here-and-why-it-outranks-a-model). Measurements below come from the July 31 and August 15, 2026 validation runs; they are evidence for those fits, not a claim about every future fit or the current bundle inventory. The registry in `tools/gen-chs-gates.mjs` determines what ships.

## Method and acceptance criteria

Run `tools/FitValidation` with `--current` for a gate. It resolves the nearest IWLS station with `wcsp1` within 3 km, fetches speed and direction, and projects signed velocity onto the metadata flood axis. The frozen artifacts in `tools/chs-reference` fit the series in JavaScriptCore; the app's current engine synthesizes slacks and maxima. Score against held-out CHS `wcp1-events` 28–35 days ahead. Compare both 210-day and trailing 60-day fits from the same fetch. The app fits natively through Neaps; `IwlsFixtureTests` checks its coefficients against this JavaScript oracle and its predictions against recorded Victoria and Dodd holdouts.

| Quantity | Acceptance bar |
|---|---|
| Slack timing median | ≤ 15 min |
| Slack timing worst | ≤ 30 min |
| Extremum timing median, published speed ≥ 0.75 kn | ≤ 20 min |
| Peak speed median error | ≤ 0.5 kn |
| Axis | No systematic flip; wrong sign at ≥ 60% of extrema rejects the fit |

Every observed slack must have a model match within 180 minutes. A passing final fit meets all five bars. A rejected fitted model may only appear through official online predictions, with their own provenance.

A 60-day provisional answer must have measured worst slack error at or below 45 minutes. Its warning quotes the gate's rounded error bound; the provisional slack allowance does not certify peak-speed accuracy. The full model uses the gate's validated `fitDays`. Tides have a separate validation window and are not covered by these current results.

## Salish Sea measurements

All 19 candidates resolved within 0.06 km. All observed slacks matched within 180 minutes, and no systematic axis flip occurred. Timing is in minutes and speed in knots.

| Gate | fit rms | slack med/max | extrema med/max | speed med | Verdict |
|---|---|---|---|---|---|
| Active Pass | 0.05 | 2.4 / 4.0 | 1.1 / 2.4 | 0.06 | **PASS** |
| Arran Rapids | 0.63 | 4.9 / 11.4 | 14.5 / 34.5 | 0.66 | FAIL — speed |
| Beazley Passage | 0.53 | 3.6 / 10.5 | 16.2 / 39.3 | 0.51 | FAIL — speed (near miss) |
| Blackney Passage | 0.16 | 5.0 / 24.7 | 8.7 / 25.2 | 0.07 | **PASS** |
| Dent Rapids | 0.46 | 3.2 / 8.6 | 20.1 / 38.0 | 0.27 | FAIL — extrema med (near miss) |
| Dodd Narrows | 0.37 | 2.1 / 18.6 | 13.1 / 26.0 | 0.16 | **PASS** |
| First Narrows | 0.06 | 2.8 / 5.8 | 1.9 / 3.0 | 0.09 | **PASS** |
| Gabriola Passage | 0.39 | 19.2 / 33.1 | 14.9 / 38.2 | 0.22 | FAIL — slack |
| Gillard Passage | 0.39 | 3.7 / 9.1 | 12.4 / 22.8 | 0.42 | **PASS** |
| Hole in the Wall | 0.54 | 3.6 / 9.6 | 13.7 / 26.9 | 0.42 | **PASS** |
| Johnstone Strait Central | 0.04 | 1.3 / 5.4 | 4.5 / 12.8 | 0.05 | **PASS** |
| Juan de Fuca East | 0.22 | 18.1 / 84.5 | 22.6 / 46.7 | 0.11 | FAIL — slack |
| Porlier Pass | 0.38 | 2.2 / 18.8 | 10.6 / 38.1 | 0.16 | **PASS** |
| Race Passage | 0.32 | 4.2 / 11.6 | 9.9 / 50.4 | 0.44 | **PASS** |
| Sechelt Rapids | 1.29 | 15.5 / 39.5 | 11.7 / 55.7 | 0.94 | FAIL — slack + speed |
| Second Narrows | 0.35 | 5.9 / 13.5 | 20.6 / 48.1 | 0.26 | FAIL — extrema med (near miss) |
| Seymour Narrows | 0.00 | 0.2 / 1.0 | 0.3 / 0.5 | 0.00 | **PASS** |
| Tillicum Bridge | 0.43 | 19.0 / 93.0 | 19.1 / 96.5 | 0.15 | FAIL — slack |
| Weynton Passage | 0.21 | 3.0 / 19.2 | 5.6 / 25.5 | 0.12 | **PASS** |

## Short-window comparison

| Gate | 60 d slack med/max | 210 d slack med/max | Ships as |
|---|---|---|---|
| Active Pass | 1.8 / 3.2 | 2.4 / 4.0 | **60 d, final** |
| First Narrows | 2.6 / 4.8 | 2.8 / 5.8 | **60 d, final** |
| Johnstone Strait Central | 3.8 / 11.4 | 1.3 / 5.4 | **60 d, final** |
| Seymour Narrows | 0.2 / 1.0 | 0.2 / 1.0 | **60 d, final** |
| Gillard Passage | 12.4 / 17.7 | 3.7 / 9.1 | 210 d · provisional ±20 min |
| Hole in the Wall | 10.5 / 19.7 | 3.6 / 9.6 | 210 d · provisional ±20 min |
| Race Passage | 7.8 / 28.5 | 4.2 / 11.6 | 210 d · provisional ±30 min |
| Blackney Passage | 7.2 / 31.8 | 5.0 / 24.7 | 210 d · provisional ±35 min |
| Porlier Pass | 12.3 / 32.1 | 2.2 / 18.8 | 210 d · provisional ±35 min |
| Dodd Narrows | 15.1 / 32.9 | 2.1 / 18.6 | 210 d · provisional ±35 min |
| Weynton Passage | 2.9 / 34.1 | 3.0 / 19.2 | 210 d · provisional ±35 min |
| *(not bundled)* Second Narrows | 19.3 / 45.7 | 5.9 / 13.5 | — |
| *(not bundled)* Sechelt Rapids | 27.8 / 60.4 | 15.5 / 39.5 | — |
| *(not bundled)* Tillicum Bridge | 33.3 / 79.4 | 19.0 / 93.0 | — |
| *(not bundled)* Juan de Fuca East | 24.9 / 146.6 | 18.1 / 84.5 | — |

The disposition column records the validation run's decision. Current fitted and online identities are listed in `Slackwater/Resources/chs-current-gates.json`.

## National candidates

The August 15 measurements use the same harness, held-out period, and acceptance bars.

| Gate | fit rms | slack med/max | extrema med/max | speed med | Verdict |
|---|---|---|---|---|---|
| Great Bras d'Or | 0.22 | 4.2 / 14.1 | 15.6 / 31.5 | 0.10 | **PASS** |
| Quatsino Narrows | 0.34 | 6.1 / 16.5 | 11.6 / 52.0 | 0.30 | **PASS** |
| Masset Sound | 0.35 | 4.4 / 21.0 | 23.9 / 52.4 | 0.20 | FAIL — extrema med |
| Nakwakto Rapids | 0.73 | 6.1 / 25.1 | 11.9 / 50.2 | 0.80 | FAIL — speed |

60-day scores, and how each ships:

| Gate | 60 d slack med/max | Ships as |
|---|---|---|
| Great Bras d'Or | 4.6 / 23.8 | **60 d, final** — passes the whole bar at 60 d |
| Quatsino Narrows | 14.1 / 24.4 | 210 d · provisional ±25 min |
| Masset Sound | 5.0 / 34.3 | online (never fitted) |
| Nakwakto Rapids | 11.2 / 29.6 | online (never fitted) |

## Reproduction and parity

Run `swift run -c release fit-validation --current <name> <lat> <lon> [cacheDir]` from `tools/FitValidation`. Reports and cached samples are written under `/tmp/fit-validation/`. The harness also accepts `--samples`, `--events`, `--flood`, `--ebb`, and `--label` for a file-based current check. A report's window label does not prove the input contains that many days; inspect its sample span.

[`tools/fill-pipeline/parity_check.sh`](../../tools/fill-pipeline/parity_check.sh) compares the Node and JavaScriptCore fits from the same committed artifacts and sample bytes, allowing machine-epsilon differences. Use this maintained check for fitter parity.
