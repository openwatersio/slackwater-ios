# Remote Station Catalog Refresh Design

**Issues:** [#122](https://github.com/openwatersio/slackwater-ios/issues/122), [#234](https://github.com/openwatersio/slackwater-ios/issues/234)

## Goal

Let Slackwater receive corrected, added, and removed station identity and model
data without an App Store release. A fresh install must remain fully useful
offline, a rejected candidate must leave the current snapshot untouched, and a
valid refresh must become visible in the running app immediately. Widgets must
read the new generation on their next system-permitted timeline refresh.

This design covers the catalog channel only. Refreshing fitted CHS models and
online prediction windows is a separate phase because that work is paced,
station-specific, and much larger than the catalogs.

## Decisions

- Publish complete files, not deltas or correction overlays.
- Publish all six current catalogs:
  `stations.json`, `currents.json`, `chs-stations.json`, `chs-gates.json`,
  `chs-current-gates.json`, and `chs-tombstones.json`.
- Serve fixed URLs under
  `https://tiles.openwaters.io/slackwater/catalogs/` from a dedicated
  Cloudflare Static Assets Worker owned by this repository.
- Use each asset's HTTP `ETag` as its version and `If-None-Match` for refreshes.
- Permit ordinary cellular connections, but respect Low Data Mode.
- Activate all six files as one locally validated snapshot.
- Activate a valid snapshot immediately, including after a background transfer.
- Use HTTPS and validation rather than application-level signatures.
- Keep the bundle as the permanent fallback.
- Keep `chs-tombstones.json` as the filename for compatibility, but broaden it
  into the cumulative tombstone ledger for every station kind.

## Non-goals

- Delta generation, patch ordering, or historical client/server version pairs.
- Region packs or selective catalog download.
- Refreshing CHS fitted models or online prediction windows.
- A refresh progress UI, settings, notifications, or analytics.
- Periodic polling while the app remains continuously online.
- Silent push, `BGTaskScheduler`, or guaranteed wake-up for a suspended app
  when it has no background transfer pending.
- A signing-key, rotation, or revocation system.

## Current state

The six JSON files are committed generator outputs in `Slackwater/Resources`.
The five live catalogs are loaded into immutable `static let` arrays and then
merged into immutable `StationItem.all` and `StationItem.byId` values. These
values feed search, distance ranking, map pins, navigation, fitted CHS jobs,
chart packs, favorites, recents, and widgets.

The app and widget currently share two loaders in `CurrentStation.swift`:

- `bundled(_:)` decodes a complete catalog for the app.
- `bundled(_:id:)` scans mapped compact JSON and decodes one record for the
  memory-limited widget process.

Both use `try?`. A missing, unreadable, or undecodable complete catalog silently
becomes `[]`, which is the root cause of #234. The single-record loader silently
becomes `nil`. `ChsFitService.sweepOrphans` refuses to delete models when its
  catalogs are empty, but the original catalog failure is not reported.

The App Group already provides the correct shared container for fitted models
and app/widget defaults. `Connectivity` already publishes `NWPathMonitor`
status. `ChartPackManager` and `ChsFitService` already react to observable state
changes. These existing facilities are reused.

## Published surface

The new Worker is static-only: no JavaScript request handler, manifest service,
database, or R2 pointer. Its route owns only:

```text
tiles.openwaters.io/slackwater/catalogs/*
```

The deploy stages only the six JSON resources. [Cloudflare Static Assets]
supplies content-derived ETags and conditional `304 Not Modified` responses.
The existing tiles host already serves Brotli when a client advertises
`Accept-Encoding: br`; the deployment smoke test makes that behavior a release
requirement for these new URLs.

[Cloudflare Static Assets]: https://developers.cloudflare.com/workers/static-assets/headers/

A successful Worker deployment releases its asset set together. Fixed URLs mean
that a correction to `chs-stations.json` transfers that file while the other
five answer `304`. A failed deployment leaves the previous version live.
Cloudflare's deployment rollback restores the previous six-file set together.

Publishing runs only after a push to `main` that changes one of the catalogs or
the Worker configuration. It depends on both existing data checks and the app
test lane. Pull requests validate but never publish. A post-deploy probe checks
every asset for:

- HTTP 200 and JSON content type;
- Brotli when requested;
- a non-empty ETag; and
- HTTP 304 when that ETag is sent in `If-None-Match`.

There is no separate version document. The six ETags stored with a local
snapshot describe exactly which bytes it contains.

## Catalog snapshot

The app gains one main-actor `CatalogStore`. Its immutable `CatalogSnapshot`
contains the six decoded arrays, their merged `StationItem` array and indexes,
and the six optional opaque ETag values. The store publishes only a generation
counter and the current snapshot; consumers never observe a half-built
candidate.

The on-disk layout lives in the App Group so the widget reads the same active
generation:

```text
Catalogs/
  current                         # atomically written generation name
  <generation>/
    stations.json
    currents.json
    chs-stations.json
    chs-gates.json
    chs-current-gates.json
    chs-tombstones.json
    metadata.json                 # filename -> ETag
  staging-<batch>/                # removed after commit or rejection
```

Generation directories are immutable. The app writes and validates a staging
directory, renames it to its final generation name, then atomically replaces
the small `current` pointer. A crash before the pointer replacement leaves the
old generation active. After a successful replacement, obsolete generations
and abandoned staging directories are best-effort cleanup; failure to clean
them cannot affect correctness. Cleanup needs no handshake with the widget
process: a file the widget has already opened or mapped keeps serving reads
after its directory is unlinked, and the widget's locator pins a generation
per lookup and retries whole lookups when a pinned file has disappeared (see
the widget rules below).

On process start, the store reads and validates the pointed-to snapshot
synchronously before any catalog consumer runs. If the pointer, directory,
file, decode, or validation fails, it logs the exact reason and loads the
bundled files. The stored snapshot is an optimization over the bundle, never a
prerequisite for the app to work.

## Catalog loading and #234

Catalog load functions return decoded values or throw a contextual error that
names the resource and whether lookup, read, decode, or validation failed. They
never manufacture an empty array. Every caught catalog error is:

- recorded with `Logger` in release builds; and
- paired with `assertionFailure` in debug builds.

The release log includes the resource name, response ETag when one exists, and
the validation reason. It does not include catalog contents, device location,
favorites, or other user data.

The app's complete-catalog accessors use the active snapshot and fall back to
the bundle as a unit. They are app-target-only forwards into `CatalogStore`.
The widget keeps the decode split `StationItem.widgetItem` ships today: the
mapped single-record scanner for the two multi-megabyte NOAA catalogs, and
whole decodes for the small CHS catalogs and the tombstone ledger. The scanner
requires the compact one-line record form the NOAA generators emit;
`chs-gates.json` and `chs-current-gates.json` are pretty-printed, which is one
reason the small catalogs are decoded whole rather than scanned. Every widget
lookup, including CHS identity and tombstone lookup, goes through a small
shared file locator. The locator pins one generation per lookup: it resolves
the `current` pointer once, and every related read in that lookup — a
subordinate record, its reference, its tombstone check — uses the pinned
directory, never a per-file re-resolution that could mix generations. If a
pinned read fails — activation can replace the generation and cleanup can
unlink it between the pointer read and the file open — the locator logs the
failure, re-resolves the pointer once, and retries the whole lookup against
the new generation. If that fails it retries the bundled files, and if the
bundle also fails it logs every failure and returns `nil`; it never
instantiates `CatalogStore`, crosses the store's main-actor boundary, or
starts network work.

This centralizes the #234 fix at the two real trust boundaries: complete
catalog loading for the app and widget-side record loading.

## Refresh lifecycle

`CatalogStore` owns one background `URLSession` with a stable identifier. The
configuration:

- uses download tasks so iOS can continue transfers while the app is suspended;
- relies on background sessions' inherent connectivity waiting;
- allows expensive cellular access;
- disallows constrained Low Data Mode access; and
- asks iOS to relaunch the app for background-session completion events.

A minimal `UIApplicationDelegate` connected with
`UIApplicationDelegateAdaptor` receives
`application(_:handleEventsForBackgroundURLSession:completionHandler:)`. It
routes only the catalog session identifier to the store, retains the system
completion handler, and recreates the session with the same identifier and
configuration. After `urlSessionDidFinishEvents(forBackgroundURLSession:)`, it
calls the completion handler on the main thread only after the restored staged
batch has activated or been rejected. This follows Apple's [background-session
lifecycle] so iOS can suspend the relaunched app cleanly.

[background-session lifecycle]: https://developer.apple.com/documentation/foundation/downloading-files-in-the-background

One batch creates six download tasks. Each request uses its active file's ETag
in `If-None-Match`; ETags are opaque strings and are stored and replayed without
normalization. Task descriptions carry the batch and catalog names so a
relaunched process can reconnect delegate callbacks to staging files. Staging
markers distinguish a downloaded file, `304`, and a terminal request failure.
If the process stops after transfer completion but before validation, the next
store initialization finishes or rejects the staged batch.

Refresh triggers are:

- app launch;
- entry into the foreground; and
- an offline-to-online transition observed by `Connectivity`.

Concurrent triggers coalesce with the tasks already registered in the
background session. A fully unchanged batch returns six `304` responses and
does not create a new generation.

iOS can complete a queued transfer after suspension or relaunch the app for its
completion. It does not promise to wake a fully suspended process merely because
connectivity changed when no transfer was pending. This phase does not pretend
otherwise: silent push and background scheduling are deferred until a measured
case justifies them.

## Candidate assembly

Each catalog is handled independently at the HTTP boundary:

- `200`: save the downloaded bytes and response ETag in staging;
- `304`: reuse the active bytes and ETag;
- transport or HTTP failure: reuse the active bytes and ETag;
- unreadable or undecodable `200`: log it, reuse the active bytes and ETag, and
  leave the old ETag active so the bad response is retried later.

On a fresh install, the bundle acts as the active bytes and has no ETags. This
allows a partial first refresh to activate useful changes when the resulting
six-file candidate is valid, without ever making connectivity a launch
dependency.

After all tasks reach a terminal state, the app decodes and validates the whole
candidate. Successfully downloaded files whose combined snapshot fails
validation do not advance their active ETags; the next trigger retries them.

## Validation

Validation is pure and runs before persistence or publication. A candidate must:

1. Decode every file into its existing record type.
2. Keep every live catalog and the cumulative tombstone ledger non-empty.
3. Give every record a non-empty ID and name, finite coordinates within valid
   latitude/longitude bounds, and a recognized IANA time-zone identifier where
   the record carries one.
4. Keep IDs unique within each file and keep rendered `StationItem.id` values
   unique across live catalog kinds.
5. Give harmonic tides and non-subordinate currents usable constituent data;
   give subordinate tides both offsets and a live tide reference.
6. Resolve every subordinate tide reference within `stations.json`.
7. Give every subordinate NOAA current all four finite time offsets and two
   finite, non-negative speed ratios, at least one of which is positive. Its
   `reference` must resolve within `currents.json` to a non-subordinate record
   with usable constituents.
8. Resolve every NOAA current `tideReference` within `stations.json`.
9. Resolve every derived gate `reference` and every CHS current
   `tideReference` within `chs-stations.json`.
10. Keep tombstone IDs disjoint from all live `StationItem` IDs.
11. Include a tombstone for every rendered station ID present in the active
    snapshot but absent from the candidate.
12. Preserve every tombstone in the active snapshot unless that exact rendered
    ID is live again in the candidate.
13. Keep `stations.json` and `currents.json` in the compact record form the
    widget scanner requires: the validator locates a sampled record in each
    file with the single-record decoder itself.

Current catalog-specific invariants already covered by generator tests remain
there; the runtime validator protects the app from incomplete, corrupt, or
cross-inconsistent published bytes rather than trying to reimplement every
scientific generator check in Swift.

An empty live catalog is deliberately invalid in this phase, including the
one-entry derived-gate catalog. If an entire station kind is intentionally
retired, that policy change needs an app release that explicitly relaxes the
invariant; a remote payload cannot make that decision silently.

## Tombstones and stable IDs

Favorites, recents, fitted models, gates, and pairings all use station IDs as
join keys. Remote delivery increases the speed of catalog changes but must not
weaken that contract.

The existing `StationTombstone` record already has the provider-neutral shape
needed by every station kind. `chs-tombstones.json` becomes a cumulative ledger
for removed rendered IDs:

- NOAA currents use their rendered `current:<record-id>` ID;
- NOAA/TICON tides use their record ID;
- CHS ports and both CHS gate kinds use their existing bare ID.

Generator work updates the ledger for every live catalog, preserves historical
rows, removes a tombstone if that exact rendered ID becomes live again, and
rejects a live/tombstone collision. A rename or position correction retains the
same ID. An apparent renumber therefore leaves the old favorite as an explicit
removed-station row instead of silently orphaning it.

The client enforces the active-to-candidate removal rule even if publishing
checks regress. It cannot determine whether a tombstoned removal plus a new ID
was a legitimate replacement or an accidental renumber, so generator review
remains the place that prevents renumbering; runtime validation prevents silent
data loss.

## Immediate activation

The model types remain the public surface used throughout the app. In the app
target, their `all`/`byId` accessors become computed forwards into
`CatalogStore.snapshot` instead of separately initialized `static let` values.
The merged arrays and indexes are computed once when a snapshot is built, not
on every accessor. Widget code uses only the shared file locator and the two
widget decode paths described above; it never calls these app accessors.

When the current pointer has been replaced, the store publishes one generation
change on the main actor. That change causes the following bounded reactions:

- `StationListView` re-renders from the new arrays.
- `RankedStations` includes the generation in its memoization key.
- `PinFeaturesCache` includes the generation in its cache key, and a visible map
  remounts its source.
- `ChsFitService` rebuilds catalog-derived candidates, preserves matching queue
  status and stored models, drops removed jobs, rebuilds fitted records from the
  new identity, and resumes eligible pending work.
- `ChartPackManager` reconciles so corrected station positions update desired
  packs.
- The nearest-widget station cache is recomputed when a current location exists.
- `WidgetCenter.reloadAllTimelines()` requests the earliest
  [system-permitted widget refresh]; the next timeline reads the shared active
  generation.

[system-permitted widget refresh]: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/

Navigation currently stores complete record values in `NavigationPath`.
Converting every destination to an ID route solely for rare catalog activation
would broaden this work substantially. The list therefore clears its navigation
path when the generation changes. The sailor returns to the refreshed list
rather than seeing an open detail backed by stale record bytes.

Removed fitted-model files are not deleted during activation. Removed jobs stop
running immediately; the existing guarded orphan sweep can reclaim their files
on the next launch. This avoids adding a new destructive path to a refresh
callback.

## Failure behavior

| Failure | Result |
|---|---|
| Offline at launch | Bundle or last valid snapshot renders; background tasks wait. |
| One request fails | Its active file participates in candidate validation. |
| Server returns corrupt JSON | Error is logged; that file and ETag stay active. |
| Candidate has broken cross-references | Whole candidate is rejected; active pointer is unchanged. |
| App stops during download | Background session continues or retries on the next trigger. |
| App stops during staging | Old pointer remains active; staging is finalized or removed next launch. |
| Active stored snapshot is corrupt | Error is logged and the complete bundle loads. |
| Bundled file is corrupt | Debug assertion and release log identify the file; CI is expected to prevent shipment. |
| Worker deployment fails | Previous Worker assets remain live. |
| Published set rolled back after clients activated it | Rule 11 rejects the older set on those clients; they keep their newer snapshot until a corrective deployment publishes a ledger-preserving set. |
| New schema cannot decode on an older client | That client logs and retains its last valid snapshot or bundle. |

## Verification

Focused Swift tests cover:

- missing and malformed files produce named errors rather than empty arrays
  (#234);
- a valid correction builds a new generation;
- an invalid `200` retains the active file and ETag;
- duplicate IDs, invalid identity fields, empty catalogs, broken references,
  live/tombstone collisions, and un-tombstoned removals reject a candidate;
- subordinate currents with an unresolved or subordinate reference, missing
  corrections, non-finite offsets, negative ratios, or two zero ratios reject
  a candidate;
- a NOAA catalog re-serialized out of compact record form rejects a candidate;
- a correctly tombstoned removal validates;
- dropping a historical tombstone without restoring its station rejects a
  candidate;
- adding a station, activating it, then serving the prior set again keeps the
  newer snapshot active, and a corrective set whose ledger tombstones the
  retracted ID activates;
- interruption before pointer replacement leaves the old generation active;
- stored-snapshot corruption falls back to the bundle;
- CHS queue reconciliation preserves surviving work, updates fitted-record
  identity, and drops removed jobs;
- catalog generation invalidates station ranking, pin features, and chart-pack
  inputs; and
- the widget resolves active records from every catalog kind and the tombstone
  ledger — exercising the actual generated resource files through both the
  NOAA single-record scanner and the small-catalog whole decodes — falls back
  to bundled records after active-file corruption, and does not instantiate
  the complete catalog store;
- activation or cleanup between related widget reads causes one whole-lookup
  retry against the new generation, never a mixed-generation result;
- a restored background session finishes or rejects its staged batch before
  invoking the saved UIKit completion handler on the main thread.

Existing generator, catalog, app, and widget tests remain required. The publish
job runs only after the data and app jobs pass, then performs the live six-file
Brotli/ETag/304 smoke test.

## Rollout

The Worker may deploy before or with the client; existing releases never request
the new URLs. The first supporting app release starts from its bundle and has no
ETags, so its first connected refresh downloads all six files. Subsequent
refreshes transfer only changed assets.

If client problems appear, roll back the app change in a normal release; its
bundle remains complete.

Worker deployment rollback covers serving problems: a failed deploy, broken
headers, an asset set that never validated anywhere. It cannot retract catalog
content that clients have already activated. A client that activated release B
holds B's additions as active IDs, so a rolled-back set that lacks those
stations and their tombstones fails validation rule 11 there; that client
keeps B until the server moves forward. Retracting content is therefore a
corrective deployment, not a rollback: revert the source change, regenerate so
the cumulative ledger tombstones every retracted ID, and publish the result.
Clients still on the older set never see the retracted stations; clients on B
activate the correction as an ordinary refresh. No server-side migration or
remote state must be reversed.
