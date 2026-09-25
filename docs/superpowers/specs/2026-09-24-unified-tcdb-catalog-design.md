# Unified TCDB catalog

## Intent

Slackwater uses one versioned TCDB as the source of station identity, stable routes, licensing, and prediction records across its Node generators, iOS app, and widget extension. The app and widget memory-map the file and read only the identity or prediction bytes they need.

The bundled database contains every upstream station identity. It retains prediction payload only for the exact station set Slackwater can render. This keeps unavailable-station explanations complete without redistributing restricted harmonic data or silently widening the prediction catalog.

Success means:

- one exact database release supplies the Node and Swift readers;
- stored station IDs, favorites, widget selections, shared links, former routes, and unavailable stations keep resolving;
- NOAA tide and current records use the same mapped database;
- CHS identity and tide references come from TCDB while downloaded observations and fitted models stay local;
- the large tide, current, station-index, and slug JSON resources leave the runtime bundle;
- parity checks name every intentional catalog difference.

## Upstream dependency

The integration targets `openwatersio/slackwater-database` version `1.0.0-beta.0`, including the APIs requested on tide-database PR #192. The database packages remain at that beta until the Slackwater app releases. `project.yml` pins the Swift package exactly, and `tools/package.json` pins `@slackwater/database` to the same version.

The public Swift API uses domain types instead of generated FlatBuffers accessors:

```swift
StationDatabase
StationDatabase.station(id:)
StationDatabase.stationRoute(kind:slug:)
StationDatabase.stationRoutes(kind:)
StationRoute(slug:stationIDs:formerPaths:)
```

`Station` exposes typed current fields and offsets, structured location, source and license information, quality status, and prediction data. Slackwater does not import or name generated `Slackwater_*` types.

The public root type is `StationDatabase`, since the same collection contains tide and current records. The `TCDB` file identifier and `.tcdb` extension remain format names.

## Bundled database

The generated artifact is `Slackwater/Resources/slackwater.tcdb`. Both the app and widget targets bundle this file.

The generator starts from every station in `@slackwater/database`. It applies the existing Slackwater selection rules once, including commercial-use permission, freshwater exclusion, CHS coverage, datum checks, duplicate removal, current direction requirements, and complete subordinate/reference pairs.

Every input station contributes its identity, location, aliases, provenance, license, and attribution. A selected station also contributes the prediction fields required by its station kind. A non-selected station has no constituents, datums, astronomical bounds, or subordinate prediction offsets in the output.

The app-specific file's inline `accepted` field identifies records Slackwater can render. Its quality reason distinguishes the small unavailable-station set from records hidden for duplication, freshwater, quality, or coverage reasons. The unavailable set follows the same rules as PR #427: non-commercial reference stations, outside excluded freshwater networks, with no renderable station within 50 km, and with a usable place identity. No restricted prediction value enters the artifact.

Routes remain complete. Route resolution returns station IDs, then the app decides whether the target is renderable, unavailable, or absent. Former routes continue pointing to the same identity and never fall through to a different station.

## Generator flow

The Node pipeline has one selection result in memory and writes all derived artifacts from it:

1. Load the pinned database's stations and routes.
2. Classify every identity as renderable tide, renderable current, CHS identity, unavailable, or hidden.
3. Build `slackwater.tcdb`, stripping prediction fields from every non-renderable record.
4. Generate the remaining small CHS fitting-policy and tombstone artifacts from the same classified records.
5. Run parity checks before replacing committed resources.

The current generator reads unified TCDB current records instead of `data/noaa-currents.json`. Current offset minutes convert to the engine's seconds at the adapter boundary. Missing-value flags remain distinct from real zeroes. Non-primary NOAA bins remain lookup-only references and never appear as list stations.

CHS generators read identity, source, location, derived-current rules, and tide references from TCDB. TCDB covers `ChsStationInfo` and `ChsGateInfo` completely. The small current-gate policy artifact retains app-specific fitting fields that the shared schema does not model, including fit windows, provisional error limits, and online-only gates. CHS observations, offline downloads, and fitted coefficients remain device-generated under the existing license boundary.

`@openwaters/station-metadata`, the NOAA current bundle, their vendored data path, and the temporary route-package alias leave the tool dependency graph after parity passes.

## Swift integration

A small Slackwater adapter owns the mapped `StationDatabase` and converts one upstream station into the existing `TideStationRecord`, `CurrentStationRecord`, or station identity shape. Existing prediction and view code keeps those types.

The app builds `StationItem.all` from an identity scan of accepted TCDB records. The adapter selects the correct tide, current, CHS tide, or CHS derived-current case and joins the small CHS current-gate policy by ID. The scan reads no constituents. Full tide and current records resolve by binary station ID lookup when a detail, card, fitting operation, or prediction needs one.

The widget opens the same mapped file through `CatalogFileLocator`, resolves its selected ID, and reads only that station and any subordinate reference. It does not build the full station list.

Shared-link parsing asks TCDB for a tide or current route by slug. Sharing finds the route that contains the station ID. A small in-memory reverse map may be built lazily because sharing is an explicit action and route data is already mapped. `slugs.json` and `SlugTable` are removed.

`stations.json`, `currents.json`, `station-index.json`, their full-array decoders, and the compact JSON record scanner are removed after the app and widget use TCDB. Codable stays where CHS fits, saved state, test fixtures, and other JSON resources still need it.

## Stored state

Station IDs remain the durable identity. Favorites, recents, widget selections, deep links, and tombstones continue storing their existing IDs, including the `current:` UI prefix where it already forms part of `StationItem.id`.

Chosen namesake state stores station IDs as values but keys the local dictionary by `<series>|<name>`. On load, the store rebuilds each key from the current item found by its stored ID. This preserves a choice across upstream renames without maintaining a rename table. Cloud values already carry station IDs and follow the same normalization.

The current prefix remains an app presentation concern. TCDB lookup and route tables use the underlying catalog ID.

## Validation and failure behavior

Generation refuses to write an artifact when:

- a renderable station lacks required identity, timezone, prediction data, or a required reference;
- a non-renderable station retains any prediction field;
- rendered IDs collide across tide, current, and CHS station kinds;
- a baseline live ID disappears without a tombstone or an explicit parity decision;
- a route points to a different identity than the pinned source;
- a current missing-value flag is collapsed into a numeric zero.

The bundled file is opened once. A missing, unreadable, or invalid bundled TCDB is terminal because the app has no station catalog to show. Widget lookup returns no timeline station and follows its existing fallback behavior.

Remote TCDB activation is outside this change. A release number and file identifier do not prove schema compatibility or full buffer validity. `CatalogStorage` may locate the bundled binary alongside remaining JSON generations, but it does not activate downloaded TCDB bytes until the remote-catalog work defines a versioned compatibility and verification contract.

## Parity checks

Tests compare the committed baseline resources with the generated TCDB before the JSON files are deleted. The report covers:

- renderable, unavailable, hidden, reference-only, and tombstoned IDs;
- names, regions, aliases, coordinates, timezones, sources, and licenses;
- tide and current routes, former paths, and route collisions;
- current directions, mean flow, tide references, subordinate offsets, and missing values;
- reference tides, ratio and fixed tide subordinates, harmonic currents, and subordinate currents;
- chart-datum shifts and astronomical bounds within an explicit Float32 tolerance;
- stored favorites, namesake choices, widget selections, and deep links.

Swift tests start red against the wished-for adapter API, then cover mapped identity scans, station lookup, current conversion, subordinate references, route lookup, unavailable identity, corrupt input, app fallback, and widget lookup. The final verification runs the Node data suite and the app/widget test suite offline.

## Rollout

The cutover keeps the baseline JSON resources until their TCDB parity checks pass. Removal happens in the same branch as the consumer switch so no build can ship both runtime paths accidentally.

The implementation records release measurements for cold open, identity scan, first and repeated tide/current lookup, widget lookup, and memory use. Distance sorting and unrelated launch work remain outside these numbers.

## Out of scope

- enabling remote TCDB downloads;
- changing the prediction engines;
- moving CHS observation downloads or fitted models into TCDB;
- changing station IDs or the `current:` UI prefix;
- maintaining a second Swift FlatBuffers reader inside Slackwater.
