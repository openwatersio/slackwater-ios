# Generated data

Do not edit these committed artifacts directly:

- `chs-stations.json` and `chs-tombstones.json` — `tools/gen-chs-stations.mjs`
- `stations.json` — `tools/gen-tides.mjs`
- `currents.json` — `tools/gen-noaa-currents.mjs`
- `chs-gates.json` and `chs-current-gates.json` — `tools/gen-chs-gates.mjs`
- `station-index.json` — `tools/gen-station-index.mjs`, the identity fields of
  `stations.json` and `currents.json` and nothing else. It is what the station
  list renders from, so it is regenerated from those two files whenever they
  change and can never name a station they don't ship.

Their canonical station metadata comes from the packages and sources read by those
generators, including `@sailingnaturali/station-corrections`. Change the canonical
source first, then regenerate with `cd tools && npm run build:data`.
