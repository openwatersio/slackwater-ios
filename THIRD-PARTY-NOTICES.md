# Third-party notices

Slackwater is © Open Water Software, LLC and licensed under [GPL-3.0](LICENSE.md). It builds on the following third-party code and data. A subset of this attribution appears in the app under Settings → Data & attribution.

## Code

- [slackwater-engine](https://github.com/openwatersio/slackwater-engine) — the harmonic prediction engine, a Swift port of [Neaps](https://github.com/neaps/neaps). MIT.
- [MapLibre Native](https://github.com/maplibre/maplibre-native) — map rendering. BSD-2-Clause.
- [Almanac](https://github.com/openwatersio/almanac) — sun and moon calculations. MIT, with algorithms translated from [Astronomy Engine](https://github.com/cosinekitty/astronomy) (MIT, © Don Cross).
- [@openwaters/station-metadata](https://github.com/openwatersio/station-metadata) — station names, regions, aliases, and tide/current pairings, consumed at build time by the data generators in `tools/`. MIT.
- [@neaps/tide-database](https://github.com/neaps/tide-database) and [@neaps/tide-predictor](https://github.com/neaps/neaps) — build-time inputs for the bundled tide stations. MIT.

## Data

- **NOAA CO-OPS** harmonic constituents and current predictions — United States government work, public domain.
- **TICON-4** harmonic constants, [SEANOE](https://www.seanoe.org/data/00980/109129/) — CC BY 4.0.
- **VersaTiles** satellite tiles — imagery sources at [versatiles.org/sources](https://versatiles.org/sources), cached on the device for offline use.
- **GSC Canada West Coast Topo-Bathymetric DEM** — Canadian channel bathymetry. Contains information licensed under the [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).
- **NOAA National Bathymetric Source** — United States channel bathymetry, public domain.

Channel cross-sections for grown current patches are derived from the bathymetry above; raw survey data is not included.

## Canadian Hydrographic Service

The app bundles no CHS-published data. Canadian station identity (names, positions, aliases) is original authored metadata; predictions for Canadian stations are fetched by each user directly from the CHS [IWLS API](https://api.iwls-sine.azure.cloud-nuage.dfo-mpo.gc.ca/swagger-ui/index.html) and fitted on their device. Fitted models stay on the device and are never redistributed.
