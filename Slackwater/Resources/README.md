# Generated data

Do not edit these committed artifacts directly:

- `chs-stations.json` and `chs-tombstones.json` — `tools/gen-chs-stations.mjs`
- `stations.json` — `tools/gen-tides.mjs`
- `currents.json` — `tools/gen-noaa-currents.mjs`
- `chs-gates.json` and `chs-current-gates.json` — `tools/gen-chs-gates.mjs`

Their canonical station metadata comes from the packages and sources read by those
generators, including `@openwaters/station-metadata`. Change the canonical
source first, then regenerate with `cd tools && npm run build:data`.
