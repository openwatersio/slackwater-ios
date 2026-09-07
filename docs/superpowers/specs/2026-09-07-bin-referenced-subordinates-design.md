# Subordinate Current Stations Whose Reference Is a Non-Primary Bin

**Issue:** [#269](https://github.com/openwatersio/slackwater-ios/issues/269)
(follow-up to [#268](https://github.com/openwatersio/slackwater-ios/issues/268))

## Goal

Ship the 147 NOAA subordinate current stations that #268 drops because their
reference is a non-primary bin of a reference station (14 distinct bins, e.g.
`EPT0003@11`). The reduction needs the bin's constituents on the device; the
user must never see the bin as a station.

## The data

- All 14 bins are `type: "harmonic"` in the vendored extract, with 24 to 31
  non-zero constituents and both set directions.
- Every bin shares its exact latitude and longitude with its surface station
  (the record without `@`).
- Three surface stations (`ACT8851`, `ACT8856`, `PCT0666`) are themselves
  subordinates; their bin is the only harmonic record at that position. This
  changes nothing below: the surface record keeps shipping as a subordinate,
  and the bin ships as a reference-only record.
- None of the 147 subordinates has a published slug in station-metadata
  (v5.2.0 allocated slugs for the 1,549 that #268 shipped).
- Four of the 147 publish one set direction and null for the other; the
  existing direction filter drops them, as it dropped nine in #268. One bin
  serves only those four. So the shipped result is **143 subordinates and 13
  reference-only records**, on top of today's 1,549 subordinates.

## Decisions

- **Reference-only records live in `currents.json`**, alongside the stations
  they serve, marked `referenceOnly: true`. Not a separate catalog, not
  constituents inlined into each subordinate.
- **A reference-only record is a harmonic record.** Same fields, resolved name
  and region, constituents, `meanFlow`, both directions, timezone. No offsets,
  no `reference`, no `tideReference`. The only addition is the flag.
- **Its name is the surface station's resolved name, with no depth or bin
  label.** NOAA's extract carries no depth to quote, and "bin 11" means nothing
  to a user. The detail footer of a subordinate therefore reads exactly as it
  does for a surface reference: "NOAA subordinate station: Estes Head,
  Eastport's slacks and maxima, corrected by published offsets".
- **The flag is explicit**, not inferred from `@` in the id. The id stays the
  NOAA id (`noaa/EPT0003@11`) so a reference resolves by the same string NOAA
  uses.
- **Reference-only records have no slug** and are exempt from the slug table.
  They are not linkable, which is the point.
- **The 147 subordinates get slugs in station-metadata first**, in a release,
  before the ios change lands. Same sequence as station-metadata #37 then
  slackwater-ios #270.

## Non-goals

- Any depth, bin or layer label in the UI.
- Making a bin openable, searchable or pinned.
- Changing the reduction, the engine, or the tide side.

## Generator (`tools/gen-noaa-currents.mjs`)

1. Compute the set of bin ids referenced by a subordinate that survives every
   other filter (type, non-zero constituents, both directions).
2. Relax the primary-bin filter: keep a record whose id contains `@` only when
   it is in that set. It then flows through the existing map with two
   differences: `resolve()` is called with the surface station's id
   (`noaa/EPT0003`) so name, region and aliases match the surface station, and
   the output carries `referenceOnly: true`.
3. The orphan filter is unchanged. Its `shipped` set is every non-subordinate
   record, which now includes the bins, so the 147 pass.
4. Guard: every `referenceOnly` record is referenced by at least one shipped
   subordinate, else throw. The surviving-subordinate set in step 1 makes this
   true by construction; the guard is there for the next person who reorders
   the filters.
5. Summary line adds the reference-only count and the count of subordinates
   they serve.

The header comment's filter 2 ("Primary bin only") is rewritten to describe the
exception.

### `tools/gen-slugs.mjs`

`narrow("current", ...)` skips records with `referenceOnly` when reading
`currents.json`. Everything else in the file already has a slug or throws.

### Generator tests (`tools/gen-noaa-currents.test.mjs`)

- `noaa/ACT0091` (Eastport, Friar Roads) ships with
  `reference: "noaa/EPT0003@11"` and all six offsets.
- Exactly 13 `referenceOnly` records; each has non-empty constituents, both
  directions, no `reference`, no offsets, and is referenced by at least one
  subordinate.
- The existing "every subordinate's reference ships" test now covers 1,692
  subordinates; raise its floor from 1,500 to 1,650.

## App

### `CurrentStationRecord`

Add `var referenceOnly: Bool? = nil`, decoded like the other optional fields.
Nothing else on the record changes. `CurrentStationRecord.all` and `.byId`
keep every record, so `referenceRecord` resolves a bin exactly as it resolves a
surface station.

### `StationItem.all`

Filter `CurrentStationRecord.all` to `referenceOnly != true` before mapping.
This one filter is what hides the bin from search, the list, the map pin layer,
nearest-station location, App Intents, and share links, because all of them
read `StationItem.all` or `StationItem.byId`.

### `CatalogSnapshot`

The `groups` table applies the same filter to `currents` so a downloaded
catalog renders the same set. Validation of a reference-only record is already
correct: it has no `reference`, so it takes the "unusable constituents" branch
and passes with real constituents.

### Widget

No change. `WidgetStationLoader` resolves a subordinate's reference with the
single-record scanner over `currents.json`, and the bin is in the file. The
scanner's marker includes the closing quote, so `noaa/EPT0003"` does not match
`noaa/EPT0003@11"`.

### Map pins

`ReferenceCurrentEvents` caches events per reference id; the reference set
grows from 50 to 63. Re-run the pin budget test and re-base it only if it
fails.

### Swift tests (`SlackwaterTests/SubordinateCurrentTests.swift`)

- `noaa/ACT0091` decodes with reference `noaa/EPT0003@11`, resolves
  `referenceRecord`, and draws a non-flat 24 h curve.
- `CurrentStationRecord.byId["noaa/EPT0003@11"]` is non-nil and
  `StationItem.byId["current:noaa/EPT0003@11"]` is nil.
- `StationItem.search("Estes Head", near: (44.888, -66.996))` returns one
  current result, `current:noaa/EPT0003`.
- `NationalScaleTests`' id-uniqueness and count assertions still pass.

## station-metadata

Run the allocator against the regenerated `currents.json` (143 new current
slugs, nothing moved, nothing departed), release v5.3.0, and bump the
`@openwaters/station-metadata` dependency in `tools/package.json`. Bins are
not in the input because the ios generator flags them and gen-slugs skips
them; confirm the allocator sees no `@` id.

## Sequence

1. slackwater-ios generator change, run locally to produce the 143 ids.
2. station-metadata PR: allocate, release v5.3.0.
3. slackwater-ios PR: bump the dependency, regenerate, app change, tests.

## Testing

`cd tools && npm test` (regenerates and runs the node tests), then the
`SubordinateCurrentTests`, `NationalScaleTests`, `WidgetStationLoaderTests`
and pin budget suites in Xcode.
