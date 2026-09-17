# Generated data

Do not edit these committed artifacts directly:

- `chs-stations.json` and `chs-tombstones.json` — `tools/gen-chs-stations.mjs`
- `stations.json` and `unavailable-stations.json` — `tools/gen-tides.mjs`. The
  second is the complement of the first's commercial-use filter: identity for
  stations that exist, that upstream states we may not use, and that nothing
  we ship comes within 50 km of (issue #401). Identity only — the generator
  throws if a constituent reaches it.
- `currents.json` — `tools/gen-noaa-currents.mjs`
- `chs-gates.json` and `chs-current-gates.json` — `tools/gen-chs-gates.mjs`
- `station-index.json` — `tools/gen-station-index.mjs`, the identity fields of
  `stations.json` and `currents.json` and nothing else. It is what the station
  list renders from, so it is regenerated from those two files whenever they
  change and can never name a station they don't ship.

Their canonical station metadata comes from the packages and sources read by those
generators, including `@openwaters/station-metadata`. Change the canonical
source first, then regenerate with `cd tools && npm run build:data`.
