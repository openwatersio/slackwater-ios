# Dedicated Catalog Repository and GitHub Release Delivery Design

**Issues:** [#122](https://github.com/openwatersio/slackwater-ios/issues/122),
[#234](https://github.com/openwatersio/slackwater-ios/issues/234)

**Revises:** [Remote Station Catalog Refresh Design](2026-09-05-catalog-refresh-design.md)

**Context:** [PR #278 review](https://github.com/openwatersio/slackwater-ios/pull/278#issuecomment-5563495806)
and [follow-up](https://github.com/openwatersio/slackwater-ios/pull/278#issuecomment-5574543555)

## Goal

Make one reviewed GitHub Release the source of all six Slackwater station
catalogs, and let the iOS app activate a new release without an App Store
release.

The release must remain reproducible and reviewable. The client must remain
fully useful offline, must never activate a partial or invalid release, and
must retain its bundled or last-known-good snapshot when GitHub is unavailable.

This document supersedes the previous design's Cloudflare Worker, fixed asset
URLs, per-file ETags, and mixed-version candidate assembly. Its catalog
validation, atomic local storage, immediate activation, widget loading,
tombstone, and fallback decisions remain in force.

## Decision

- Create `openwatersio/slackwater-catalog`.
- Publish each catalog version as a GitHub Release whose assets are the six
  existing JSON files plus a small manifest. No npm package, CDN, Worker,
  bucket, or sync job.
- Keep the six existing JSON filenames and schemas.
- Publish complete, immutable releases; never publish deltas.
- Discover the current release with one conditional request to the
  `releases/latest/download/` manifest URL. Never call `api.github.com` from
  the app.
- Fetch the catalog files from that release's exact-tag asset URLs.
- Verify every downloaded file against the manifest before running the
  existing whole-snapshot validation and atomic activation.
- Enable GitHub's immutable releases on the repository.
- Keep a complete catalog snapshot in every app bundle as the permanent offline
  fallback.

The release path is:

```text
upstream data packages + committed IWLS snapshot
                    |
                    v
        slackwater-catalog generators
                    |
                    v
        reviewed six-file catalog snapshot
                    |
                    v
   tag v<version> on main -> GitHub Release + 7 assets
                    |
          +---------+----------+
          |                    |
          v                    v
 latest/download manifest   exact-tag asset files
          |                    |
          +---------+----------+
                    v
        iOS validation and atomic activation
```

## Why a dedicated repository

The review on #278 asked for releases in the database repositories to drive
the data the app uses, consumed directly as release assets. This design keeps
that shape: the app reads GitHub Release assets and nothing else. It still
needs one release to describe one coherent snapshot, because the app's
resources combine and normalize several independent inputs:

- `@neaps/tide-database` supplies tide station and constituent data;
- `@openwaters/noaa-current-stations` supplies NOAA current data;
- `@openwaters/station-metadata` supplies curated identities, corrections, and
  slugs;
- IWLS/CHS station identity data supplies Canadian station records; and
- Slackwater-specific generators add time zones, filtering, rendered IDs,
  subordinate references, gates, cross-catalog relationships, and cumulative
  tombstones.

None of those upstream artifacts has the six app schemas or can independently
guarantee their cross-file invariants. Consuming each upstream release
separately would make the app compose them, and a snapshot straddling two
upstream releases could never be validated as one unit.

The dedicated repository is therefore an app-shaped aggregation boundary, not
a new canonical marine database. Upstream repositories continue to own raw and
domain data. `slackwater-catalog` owns only the reproducible transformation into
Slackwater's published catalog contract. If a unified tides-and-currents
database later exists, its releases can replace this repository's without
changing the client, because the client contract is only "a release with these
seven assets".

## Repository contents

The initial repository stays deliberately small:

```text
catalogs/
  catalog-manifest-v1.json
  stations.json
  currents.json
  chs-stations.json
  chs-gates.json
  chs-current-gates.json
  chs-tombstones.json
inputs/
  iwls-stations.json
scripts/
  generate-*.mjs
  validate-catalogs.mjs
test/
package.json
package-lock.json
README.md
LICENSE
NOTICE
.github/workflows/ci.yml
.github/workflows/release.yml
```

The existing Node generators and their focused tests move from
`slackwater-ios/tools` instead of being rewritten. They remain plain ESM scripts
with Node's built-in test runner. `package.json` is private; nothing is
published to npm.

### Inputs

All release inputs must be pinned and available to a clean checkout:

- npm data dependencies use exact versions in `package.json` and
  `package-lock.json`, not ranges;
- the IWLS station response used by generation is committed under `inputs/`;
  and
- generator configuration that affects output is committed beside the scripts.

Generation never calls a live service. Updating the IWLS snapshot is a separate
maintainer action that produces an ordinary reviewable pull request.

### Generated outputs

The six catalogs and their manifest are committed. This lets reviewers see the
actual station additions, corrections, removals, reference changes, and
tombstones before release.

CI runs generation from a clean install and fails when the result differs from
the committed `catalogs/` directory. Generators must be deterministic: the
outputs contain no wall-clock timestamp, local path, unordered object key, or
other machine-specific value.

The repository's validator enforces the same catalog and cross-catalog rules
defined in the remote refresh design. On a pull request it also compares the
candidate with the base branch so every removed rendered station ID has a
cumulative tombstone and no historical tombstone disappears accidentally.

## Release contract

A release is a git tag `v<version>` on protected `main` and a GitHub Release
with exactly seven assets:

```text
catalog-manifest-v1.json
stations.json
currents.json
chs-stations.json
chs-gates.json
chs-current-gates.json
chs-tombstones.json
```

`version` is ordinary SemVer beginning at `1.0.0`. Patch releases carry data
changes, minor releases may add backward-compatible metadata, and the major
equals the breaking catalog schema version. The manifest schema remains the
client's authority; SemVer alone does not grant an old client permission to
accept a new schema.

The manifest filename carries the schema version. A schema-1 client requests
only `catalog-manifest-v1.json`. A future schema-2 release either attaches a
`v1` manifest and files that schema-1 clients can still use, or attaches none,
in which case those clients receive `404` and keep their active snapshot. This
is the whole schema-compatibility mechanism; there is no tag alias to move.

Every release is immutable. The repository enables GitHub's [immutable
releases], so assets cannot be added, replaced, or deleted after publication,
the tag cannot move, and the release itself cannot be deleted. A correction
always receives a greater version and is published forward.

[immutable releases]: https://github.blog/changelog/2025-09-22-immutable-releases-are-now-generally-available/

### Catalog manifest

`catalog-manifest-v1.json` is the small machine-readable contract used by the
app:

```json
{
  "schemaVersion": 1,
  "repository": "openwatersio/slackwater-catalog",
  "version": "1.0.0",
  "sources": {
    "@neaps/tide-database": "0.9.20260901",
    "@openwaters/noaa-current-stations": "0.5.0",
    "@openwaters/station-metadata": "5.2.0",
    "iwls-stations.json": "sha256:<lowercase-hex>"
  },
  "files": {
    "stations.json": {
      "bytes": 7580000,
      "sha256": "<lowercase-hex>"
    }
  }
}
```

The real manifest contains exactly the six required file entries. `bytes` is
the exact byte count and `sha256` is the lowercase SHA-256 digest of those
bytes. `sources` records exact upstream versions and the hash of the committed
IWLS input for diagnosis; clients do not interpret it.

The manifest intentionally has no timestamp. The release tag identifies the
version and the tagged commit identifies the source, so a clean rebuild is
byte-for-byte reproducible.

GitHub computes its own immutable SHA-256 `digest` for every uploaded asset
and exposes it through the Releases API. The release workflow compares those
digests with the manifest after upload. The app does not read them, because
that would require the API (see below); the manifest is the client-facing copy
of the same hashes.

## Build and review workflow

A catalog update is an ordinary pull request in the dedicated repository:

1. Update one or more pinned inputs.
2. Run the generators.
3. Review the input lockfile or IWLS snapshot, generated catalog diff,
   tombstones, and source attribution together.
4. Run generation, generator tests, full catalog validation, and transition
   validation against the base branch in CI.
5. Bump the version in `package.json` and the manifest in the same pull
   request once the candidate is accepted.
6. Merge without releasing.

Merging an upstream dependency update must not automatically publish data to
devices. The generated diff remains the review gate. Dependency-update or IWLS
refresh automation may open pull requests, but only an explicit release
publishes them.

## Release workflow

`release.yml` runs on `workflow_dispatch` from `main`, like
`tide-database/publish.yml`, and:

1. checks out `main` and proves the checkout is the protected branch head;
2. checks that `package.json` and manifest versions match and that no tag
   `v<version>` exists;
3. installs with `npm ci` on Node 24;
4. rebuilds and verifies the committed output;
5. runs all tests and catalog validation;
6. downloads the current `latest` manifest and files, verifies them, and runs
   transition validation against that exact release;
7. proves the candidate version is greater than the `latest` version;
8. creates the tag and the GitHub Release with `--latest` and the seven
   assets in one `gh release create` call, with `contents: write`; and
9. reads the release back through the API and fails loudly if any asset
   `digest` or size differs from the manifest.

The workflow uses a single non-cancelling `release` concurrency group, so two
dispatches cannot validate against the same predecessor. Step 8 passing
`--latest` explicitly avoids GitHub's default latest-selection rules, which
depend on commit dates rather than the version being released.

The first `1.0.0` release is created the same way; there is no bootstrap
exception because nothing external must be configured first. No token other
than the workflow's own `GITHUB_TOKEN` is involved.

If step 9 fails after the release exists, the release is left in place and
the maintainer publishes a corrective greater version. Immutable releases
make editing the bad one impossible by design.

## Distribution endpoints

The app uses only the redirecting download URLs on `github.com`. They are not
part of the REST API and carry no rate limit headers; the release-asset
origin they resolve to supports conditional requests and byte ranges.

Discovery:

```text
GET https://github.com/openwatersio/slackwater-catalog/releases/latest/download/catalog-manifest-v1.json
If-None-Match: <stored manifest ETag>
```

GitHub redirects this through the exact tag URL to a short-lived signed
`release-assets.githubusercontent.com` URL. The final response carries a
stable `ETag` and answers `304 Not Modified` when the stored value matches,
which the client follows through the whole redirect chain. The app stores that
ETag with its active generation. A `304` ends the refresh with no further
requests.

Files:

```text
https://github.com/openwatersio/slackwater-catalog/releases/download/v1.0.0/stations.json
```

The app constructs the remaining five URLs from the manifest `version` and the
exact allowlisted filenames. It never requests `latest/download/` for a
catalog file, so every candidate file names the same immutable release.

### Why not the Releases API

The `releases/latest` API endpoint returns the tag, asset sizes, digests, and
download URLs in one response, which would remove the manifest asset. It is
rejected for the app because unauthenticated requests are limited to 60 per
hour per originating IP, and conditional `304` responses count against that
limit unless the request carries an `Authorization` header. Sailors share
carrier-grade NAT addresses with every other unauthenticated GitHub client on
that network, and the app cannot embed a token. The download URLs have no such
limit. The release workflow, which runs authenticated, is where the API and its
digests are used.

### Transfer size

Release assets are served as stored bytes with no transfer compression. The
current catalogs total under 10 MiB, over seven of which is `stations.json`,
and the hash-reuse rule below means a release that changes only a CHS file
transfers only that file. If a full `stations.json` refresh on cellular
proves to be a problem, publish `.json.gz` assets whose manifest hashes cover
the compressed bytes and decompress with the platform's Compression framework;
this is a contained change to the generator and the staging step.

## iOS refresh lifecycle

The existing `CatalogStore`, background `URLSession`, staging directory,
snapshot validation, and atomic generation pointer remain the client design.
Discovery changes the batch from six independent fixed URLs into two ordered
steps:

1. Download the `latest/download/` manifest with the stored ETag.
2. If the response is `200` and its version is new, reuse or download each
   allowlisted catalog file from its exact-tag URL, then validate and activate
   the complete candidate.

Each step uses background download tasks and persists enough batch state to
resume after system relaunch. Launch, foreground entry, and offline-to-online
remain the refresh triggers, and concurrent triggers still coalesce.

The app compares the manifest version with its active version using a small
parser for three unsigned decimal components; no SemVer dependency is added.
An equal or older version ends the refresh without file requests, and the
manifest ETag is still recorded so the next check can answer `304`.

After accepting a new manifest, the app compares each file hash with the
active manifest. Matching files are copied from the immutable active
generation into staging; files with different hashes are downloaded from their
exact-tag URL. The bundled snapshot includes its release manifest and may be
the reuse source on a fresh install. The bundle is never modified.

Every staged file must match both the manifest byte count and SHA-256 digest
before decoding. The existing `CatalogSnapshot` validator then validates all
six files together, including cross-references, compact NOAA encoding,
tombstones, and the transition from the active snapshot. Only that complete
candidate can advance the atomic `current` pointer.

`CatalogMetadata` changes before the feature ships from per-file ETags to:

```text
repository
version
manifest schema version
manifest ETag
six file byte counts and SHA-256 hashes
```

There is no migration for the development-only ETag metadata shape. An
unreadable stored generation follows the already specified behavior: log the
reason and fall back to the complete bundle.

The signed asset URL expires about an hour after the redirect. A background
download task resolves the redirect when it actually starts, so deferred
starts are safe. Resume data that embeds an expired URL fails as a transport
error and the file is retried from the tag URL; that is not a rejection.

### Rejected versions

Releases are immutable, so repeatedly downloading the same rejected bytes
cannot repair them. The app records a rejected tuple of:

```text
(version, catalog reader revision)
```

`catalog reader revision` is a small app constant changed only when decoding or
validation compatibility changes. The app does not download the same rejected
tuple again. A greater version or a later reader revision permits a new
attempt. Transport failures, timeouts, `404` on a file, response size
violations, hash mismatches, and interrupted downloads do not mark a version
rejected; they remain retryable.

## Trust boundary and limits

The client accepts remote bytes only when all of these checks pass:

- every request uses HTTPS;
- redirects stay on `github.com` or `release-assets.githubusercontent.com`;
- the manifest names exactly `openwatersio/slackwater-catalog` and uses
  supported schema version `1`;
- the version is a valid, safe SemVer string and is embedded as one URL path
  component only after validation;
- the manifest contains exactly the six allowlisted filenames, once each;
- the manifest is at most 256 KiB;
- each file is at most 16 MiB and the complete candidate is at most 32 MiB;
- downloaded length and SHA-256 match the manifest; and
- the complete semantic and transition validator accepts the snapshot.

The download delegate cancels a task as soon as reported bytes cross its limit
and verifies the final on-disk length as well; it does not rely on a truthful
`Content-Length` header.

Hashing uses CryptoKit already provided by the platform. The manifest hashes
detect mixed files, corruption, and unexpected responses. They do not make the
manifest an independent signature: a compromised publisher able to create a
malicious but semantically valid release could change both file and hash. That
risk is controlled operationally with reviewed pull requests, protected
`main`, restricted release permissions, immutable releases, and the app's
semantic validator. An application-specific signing and key-rotation system
remains out of scope.

## Bundle synchronization

The iOS repository stops generating production catalogs from upstream source
packages. Instead it keeps one small script that takes a release tag, downloads
that release's seven assets with `gh release download`, verifies each file
against the manifest, and copies them into `Slackwater/Resources`.

The committed manifest is the pin: its `version` states which release the
bundle came from. A bundle update pull request runs the script for one tag and
reviews the resource diff. The resources remain committed and are still
validated by iOS CI. This preserves fully offline first launch and makes the
bundled version independently auditable while removing duplicate generator
ownership from the app repository.

The app records its bundled catalog version separately from an activated remote
version. A remote version is accepted only if validation succeeds; version
ordering never overrides validation. Downgrading to an older release is not a
runtime operation.

## Failure behavior

| Failure | Result |
|---|---|
| GitHub unavailable or manifest malformed | Keep bundle or active snapshot; retry on a later trigger. |
| Manifest answers `304` or reports the active version | End refresh without file requests. |
| Manifest `404` | Latest release has no schema-1 manifest; keep the active snapshot and retry later. |
| Manifest has an unsupported schema or wrong repository | Reject that immutable version. |
| File transport is missing, oversized, or has the wrong hash | Keep the active snapshot and retry later; never assemble a mixed snapshot. |
| Signed asset URL expired mid-resume | Transport failure; retry from the tag URL. |
| Files pass hashes but fail catalog validation | Reject that immutable version; leave the active pointer untouched. |
| App stops during any step | Background-session state resumes or abandoned staging is removed next launch. |
| Active stored snapshot is corrupt | Log the error and load the complete bundle. |
| Release workflow fails before creating the release | Nothing is published; `latest` is unchanged. |
| Release created but digest read-back fails | Publish a greater corrective version; never edit or delete the release. |
| Bad data was released | Publish a greater corrective version. |

## Correction and rollback

Rollback is always a forward release. If version `1.0.2` introduced bad data,
the source change is reverted, generation runs again as `1.0.3`, and the
cumulative tombstone ledger records any IDs that clients may have activated in
`1.0.2` but that the correction removes.

The release workflow compares the candidate against the current `latest`
release as a final guard, in addition to pull-request transition validation.
This prevents a release from skipping a published station generation or
silently dropping its tombstones. `latest` is never moved backward and a
release is never deleted as an operational rollback.

## Verification

The dedicated repository must prove:

- a clean install regenerates the committed catalogs byte-for-byte;
- the manifest contains exactly six entries with correct lengths and hashes;
- the full catalog and transition validator accepts the candidate;
- removed IDs require cumulative tombstones;
- `package.json` and manifest versions match and exceed `latest`;
- only the protected `main` head can release, serialized after a final
  transition check against `latest`; and
- the uploaded asset digests and sizes match the manifest.

Focused iOS tests add coverage for:

- valid and malformed manifests;
- a `304` or an equal or older manifest version causing no file requests;
- exact-tag URL construction and host/redirect rejection;
- manifest repository, version, schema, filename, size, and digest checks;
- unchanged hash reuse from the active generation;
- a file `404` or expired-URL transport failure remaining retryable;
- a hash or semantic failure leaving the active pointer unchanged, with only
  the semantic failure recording a rejected version;
- skipping the same rejected version until either version or reader revision
  changes;
- restored background sessions resuming manifest and file phases; and
- a first remote refresh from the bundle reusing unchanged files and activating
  the six-file candidate atomically.

All validation, storage, widget, activation, and #234 regression tests from the
remote refresh design remain required.

## Rollout

1. Create `openwatersio/slackwater-catalog` with immutable releases enabled,
   move the existing generators and tests, pin inputs, and release `1.0.0`
   whose six files are byte-identical to the current app bundle.
2. Verify the `latest/download/` manifest, its `304` behavior, and all six
   exact-tag file URLs from outside GitHub Actions.
3. Change the iOS repository's bundle path to the release download script,
   keeping the same committed resource bytes.
4. Implement manifest discovery, file download, rejected-version memory, and
   the already designed validation and activation lifecycle.
5. Ship the app with a bundle matching a known release. Later catalog
   releases exercise the remote path.

There is no Cloudflare migration or dual-publish period because the Worker
delivery path has not shipped. Existing app versions know only their bundle;
the first release-aware app can be released after `1.0.0` is verified.

## Non-goals

- A product-neutral tides-and-currents schema.
- Client-side composition of upstream source packages.
- An npm package, CDN mirror, Worker, object store, pointer service, or purge
  API.
- Calling the GitHub REST API from the app.
- Delta packages, region packs, or per-station downloads.
- Automatic release on every dependency or `main` update.
- Transfer compression of release assets.
- Remote CHS fitted models or online prediction windows.
- Application-level signing, key rotation, analytics, or a refresh UI.
