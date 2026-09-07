# Dedicated Catalog Repository and npm Delivery Design

**Issues:** [#122](https://github.com/openwatersio/slackwater-ios/issues/122),
[#234](https://github.com/openwatersio/slackwater-ios/issues/234)

**Revises:** [Remote Station Catalog Refresh Design](2026-09-05-catalog-refresh-design.md)

**Context:** [PR #278 review](https://github.com/openwatersio/slackwater-ios/pull/278#issuecomment-5563495806)

## Goal

Make one reviewed release the source of all six Slackwater station catalogs,
publish that release through npm's existing package machinery, and let the iOS
app activate new catalog versions without an App Store release.

The release must remain reproducible and reviewable. The client must remain
fully useful offline, must never activate a partial or invalid release, and
must retain its bundled or last-known-good snapshot when npm or its CDN is
unavailable.

This document supersedes the previous design's Cloudflare Worker, fixed asset
URLs, per-file ETags, and mixed-version candidate assembly. Its catalog
validation, atomic local storage, immediate activation, widget loading,
tombstone, and fallback decisions remain in force.

## Decision

- Create `openwatersio/slackwater-catalog`.
- Publish one public, data-only package named
  `@openwaters/slackwater-catalog`.
- Keep the six existing JSON filenames and schemas.
- Publish complete, immutable SemVer versions; never publish deltas.
- Resolve the `latest` version from the npm registry.
- Fetch the manifest and catalog files from jsDelivr using that exact version,
  never the `latest` alias.
- Verify every downloaded file against the release manifest before running the
  existing whole-snapshot validation and atomic activation.
- Publish from GitHub Releases with npm OIDC trusted publishing. Do not store an
  npm token in GitHub.
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
       GitHub Release -> npm package version
                    |
          +---------+----------+
          |                    |
          v                    v
 npm version metadata    jsDelivr exact-version files
          |                    |
          +---------+----------+
                    v
        iOS validation and atomic activation
```

## Why a dedicated repository

The app cannot consume the upstream packages directly as one coherent
snapshot. Its generated resources combine and normalize several independent
inputs:

- `@neaps/tide-database` supplies tide station and constituent data;
- `@openwaters/noaa-current-stations` supplies NOAA current data;
- `@openwaters/station-metadata` supplies curated identities, corrections, and
  slugs;
- IWLS/CHS station identity data supplies Canadian station records; and
- Slackwater-specific generators add time zones, filtering, rendered IDs,
  subordinate references, gates, cross-catalog relationships, and cumulative
  tombstones.

None of those upstream artifacts has the six app schemas or can independently
guarantee their cross-file invariants. Making the app compose them would move
generator logic, source compatibility, and partial-release handling onto every
installed device.

The dedicated repository is therefore an app-shaped aggregation boundary, not
a new canonical marine database. Upstream repositories continue to own raw and
domain data. `slackwater-catalog` owns only the reproducible transformation into
Slackwater's published catalog contract.

## Repository contents

The initial repository stays deliberately small:

```text
catalogs/
  catalog-manifest.json
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
.github/workflows/publish.yml
```

The existing Node generators and their focused tests move from
`slackwater-ios/tools` instead of being rewritten. They remain plain ESM scripts
with Node's built-in test runner. No application runtime or JavaScript API is
published.

### Inputs

All release inputs must be pinned and available to a clean checkout:

- npm data dependencies use exact versions in `package.json` and
  `package-lock.json`, not ranges;
- the IWLS station response used by generation is committed under `inputs/`;
  and
- generator configuration that affects output is committed beside the scripts.

Generation never calls a live service. Updating the IWLS snapshot is a separate
maintainer action that produces an ordinary reviewable pull request. Automating
that update can follow once its cadence warrants it; it is not part of the
release-critical path.

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

## npm package contract

The package name is `@openwaters/slackwater-catalog`. It is public and uses
ordinary SemVer beginning at `0.1.0`. Patch releases carry data changes, minor
releases may add backward-compatible metadata, and a breaking catalog schema
uses a new major version. The manifest schema remains the client's authority;
SemVer alone does not grant an old client permission to accept a new schema.

The published tarball contains only:

```text
package/package.json
package/catalogs/catalog-manifest.json
package/catalogs/stations.json
package/catalogs/currents.json
package/catalogs/chs-stations.json
package/catalogs/chs-gates.json
package/catalogs/chs-current-gates.json
package/catalogs/chs-tombstones.json
package/README.md
package/LICENSE
package/NOTICE
```

`package.json` uses an explicit `files` allowlist and
`publishConfig.access = "public"`. Generator dependencies are development
dependencies, so installing or downloading the package does not install its
source-data toolchain. The package has no `main`, `exports`, install script, or
runtime dependencies.

Each version is immutable. A published version is never overwritten,
unpublished, or reused. A correction always receives a greater version and is
published forward.

### Catalog manifest

`catalog-manifest.json` is the small machine-readable contract used by the app:

```json
{
  "schemaVersion": 1,
  "packageName": "@openwaters/slackwater-catalog",
  "packageVersion": "0.1.0",
  "sources": {
    "@neaps/tide-database": "0.9.20260901",
    "@openwaters/noaa-current-stations": "0.5.0",
    "@openwaters/station-metadata": "5.2.0",
    "iwls-stations.json": "sha256:<lowercase-hex>"
  },
  "files": {
    "stations.json": {
      "bytes": 7520000,
      "sha256": "<lowercase-hex>"
    }
  }
}
```

The real manifest contains exactly the six required file entries. `bytes` is
the exact uncompressed byte count and `sha256` is the lowercase SHA-256 digest
of those bytes. `sources` records exact upstream package versions and the hash
of the committed IWLS input for diagnosis; clients do not interpret it.

The manifest intentionally has no timestamp. The npm version identifies the
release, npm provenance identifies the publishing commit, and omitting time
makes a clean rebuild byte-for-byte reproducible.

## Build and review workflow

A catalog update is an ordinary pull request in the dedicated repository:

1. Update one or more pinned inputs.
2. Run the generators.
3. Review the input lockfile or IWLS snapshot, generated catalog diff,
   tombstones, and source attribution together.
4. Run generation, generator tests, full catalog validation, transition
   validation against the base branch, and package-content validation in CI.
5. Bump the package patch version in the same pull request once the candidate
   is accepted.
6. Merge without publishing.

Merging an upstream dependency update must not automatically publish data to
devices. The generated diff remains the review gate. Dependency-update or IWLS
refresh automation may open pull requests, but only an explicit release
publishes them.

The package-content check runs `npm pack --dry-run` and fails unless the tarball
contains the allowlisted metadata and built files and excludes generator code,
tests, raw inputs, and dependency trees.

## Release workflow

Publishing is driven by a GitHub Release whose tag is `v<package version>`.
The `publish.yml` workflow runs only when that release is published and:

1. checks that the tag, `package.json`, and manifest versions match;
2. checks out the tagged commit;
3. installs with `npm ci` on Node 24 with npm 11.5 or newer;
4. rebuilds and verifies the committed output;
5. runs all tests and catalog/transition validation;
6. verifies the packed file list; and
7. runs `npm publish` with `contents: read` and `id-token: write` permissions.

The npm package configures this repository and exact workflow filename as an
[npm trusted publisher]. The first `0.1.0` publication is the one unavoidable
bootstrap exception: after CI passes, a maintainer tags the clean commit and
publishes it manually with npm two-factor authentication, then configures
trusted publishing. Automated GitHub Releases begin with the next version. No
`NPM_TOKEN` is added to the repository. All subsequent releases use a
GitHub-hosted runner, OIDC, and automatically generated [npm provenance].

[npm trusted publisher]: https://docs.npmjs.com/trusted-publishers/
[npm provenance]: https://docs.npmjs.com/generating-provenance-statements/

After publication, the workflow polls the exact-version manifest and six file
URLs for a bounded period, verifies their hashes, and reports whether the CDN
has observed the release. Registry or CDN propagation lag does not invalidate
an already published immutable package; clients retain their active snapshot
and retry later.

## Distribution endpoints

The npm registry's [package metadata endpoint] is the release-discovery
authority:

```text
GET https://registry.npmjs.org/@openwaters%2Fslackwater-catalog/latest
```

The app decodes only the response fields it needs: `name` and `version`. It
requires the exact expected package name and a stable SemVer version made of
three unsigned decimal components. This small parser also provides the version
ordering check without adding a SemVer dependency.

The npm registry exposes package contents as a gzip-compressed POSIX tar
archive. iOS can decompress the gzip layer with AppleArchive, but Apple's
public archive stream decodes Apple Archive entries rather than POSIX tar.
Direct tarball consumption would therefore require a tar parser in the app or
a third-party package. The [jsDelivr npm CDN] already mirrors every public npm
package and exposes individual files, so neither is needed for these six JSON
files.
The app therefore fetches files at immutable exact-version URLs:

```text
https://cdn.jsdelivr.net/npm/@openwaters/slackwater-catalog@0.1.0/catalogs/catalog-manifest.json
https://cdn.jsdelivr.net/npm/@openwaters/slackwater-catalog@0.1.0/catalogs/stations.json
```

It constructs the remaining five URLs from the exact allowlisted filenames.
It never requests a jsDelivr version range, tag, omitted version, directory
listing, combine endpoint, or default file. This avoids alias caching and
version fallback semantics; every candidate file names the same immutable npm
version.

No Openwaters Worker, object-storage bucket, sync job, pointer document, or
release asset is introduced.

[package metadata endpoint]: https://github.com/npm/registry/blob/main/docs/responses/package-metadata.md
[jsDelivr npm CDN]: https://github.com/jsdelivr/jsdelivr#npm

## iOS refresh lifecycle

The existing `CatalogStore`, background `URLSession`, staging directory,
snapshot validation, and atomic generation pointer remain the client design.
Discovery changes the batch from six independent fixed URLs into three ordered
steps:

1. Download npm `latest` metadata.
2. If its version is new, download that exact version's manifest.
3. Reuse or download each allowlisted catalog file, then validate and activate
   the complete candidate.

Each step uses background download tasks and persists enough batch state to
resume after system relaunch. Launch, foreground entry, and offline-to-online
remain the refresh triggers, and concurrent triggers still coalesce.

The app compares the discovered version with its active package version. An
equal or older version ends the refresh without fetching the manifest. Normal
HTTP caching may revalidate the tiny registry response, but HTTP cache behavior
is not part of correctness.

After downloading a new manifest, the app compares each file hash with the
active manifest. Matching files are copied from the immutable active generation
into staging; files with different hashes are downloaded from their
exact-version URL. The bundled snapshot includes its release manifest and may
be the reuse source on a fresh install. The bundle is never modified.

Every staged file must match both the manifest byte count and SHA-256 digest
before decoding. The existing `CatalogSnapshot` validator then validates all
six files together, including cross-references, compact NOAA encoding,
tombstones, and the transition from the active snapshot. Only that complete
candidate can advance the atomic `current` pointer.

`CatalogMetadata` changes before the feature ships from per-file ETags to:

```text
package name
package version
manifest schema version
six file byte counts and SHA-256 hashes
```

There is no migration for the development-only ETag metadata shape. An
unreadable stored generation follows the already specified behavior: log the
reason and fall back to the complete bundle.

### Rejected versions

npm versions are immutable, so repeatedly downloading the same rejected bytes
cannot repair them. The app records a rejected tuple of:

```text
(package version, catalog reader revision)
```

`catalog reader revision` is a small app constant changed only when decoding or
validation compatibility changes. The app does not download the same rejected
tuple again. A greater package version or a later reader revision permits a new
attempt. Transport failures, timeouts, CDN `404`s during propagation, response
size violations, hash mismatches, and interrupted downloads do not mark a
version rejected; they remain retryable.

## Trust boundary and limits

The client accepts remote bytes only when all of these checks pass:

- registry and CDN requests use HTTPS;
- registry redirects remain on `registry.npmjs.org` and file redirects remain
  on `cdn.jsdelivr.net`;
- registry metadata names exactly `@openwaters/slackwater-catalog`;
- the version is a valid, safe SemVer string and is embedded as one URL path
  component only after validation;
- the manifest names that same package and version and uses supported schema
  version `1`;
- the manifest contains exactly the six allowlisted filenames, once each;
- registry metadata and the manifest are each at most 256 KiB;
- each file is at most 16 MiB and the complete candidate is at most 32 MiB;
- downloaded length and SHA-256 match the manifest; and
- the complete semantic and transition validator accepts the snapshot.

The download delegate cancels a task as soon as reported bytes cross its limit
and verifies the final on-disk length as well; it does not rely on a truthful
`Content-Length` header.

Hashing uses CryptoKit already provided by the platform. The manifest hashes
detect mixed files, corruption, and unexpected CDN responses. They do not make
the manifest an independent signature: a compromised publisher able to release
a malicious but semantically valid package could change both file and hash.
That risk is controlled operationally with reviewed pull requests, restricted
npm package ownership and GitHub release permissions, OIDC trusted publishing,
npm provenance, and the app's semantic validator. An
application-specific signing and key-rotation system remains out of scope.

## Bundle synchronization

The iOS repository stops generating production catalogs from upstream source
packages. Instead it pins an exact `@openwaters/slackwater-catalog` development
dependency and keeps a small script that copies the package manifest and six
catalog files into `Slackwater/Resources`.

A bundle update pull request changes that one exact package version, runs the
copy, and reviews the resource diff. The resources remain committed and are
still validated by iOS CI. This preserves fully offline first launch and makes
the bundled version independently auditable while removing duplicate generator
ownership from the app repository.

The app records its bundled catalog version separately from an activated remote
version. A remote version is accepted only if validation succeeds; version
ordering never overrides validation. Downgrading to an older package is not a
runtime operation.

## Failure behavior

| Failure | Result |
|---|---|
| Registry unavailable or metadata malformed | Keep bundle or active snapshot; retry on a later trigger. |
| Registry reports the active version | End refresh without CDN requests. |
| New version has not reached jsDelivr | Keep active snapshot; retry the transport failure later. |
| Manifest has an unsupported schema or wrong package/version | Reject that immutable version. |
| Manifest or file transport is missing, oversized, or has the wrong hash | Keep the active snapshot and retry later; never assemble a mixed snapshot. |
| Files pass hashes but fail catalog validation | Reject that immutable version; leave the active pointer untouched. |
| App stops during any step | Background-session state resumes or abandoned staging is removed next launch. |
| Active stored snapshot is corrupt | Log the error and load the complete bundle. |
| npm package publication fails | The previous `latest` version and all exact-version files remain available. |
| Bad package was published | Publish a greater corrective version; never overwrite, unpublish, or move `latest` backward. |

## Correction and rollback

Rollback is always a forward release. If version `0.1.2` introduced bad data,
the source change is reverted, generation runs again as `0.1.3`, and the
cumulative tombstone ledger records any IDs that clients may have activated in
`0.1.2` but that the correction removes.

The release validator compares the candidate against the current npm `latest`
package as a final guard, in addition to pull-request transition validation.
This prevents a release from skipping a published station generation or
silently dropping its tombstones. The npm `latest` tag is never moved backward
and a published package is never deleted as an operational rollback.

## Verification

The dedicated repository must prove:

- a clean install regenerates the committed catalogs byte-for-byte;
- the packed package has only the allowlisted files;
- the manifest contains exactly six entries with correct lengths and hashes;
- the full catalog and transition validator accepts the candidate;
- removed IDs require cumulative tombstones;
- tag, package, and manifest versions must match; and
- the published exact-version jsDelivr files match the npm release manifest.

Focused iOS tests add coverage for:

- valid and malformed npm metadata;
- an equal or older registry version causing no CDN requests;
- exact-version URL construction and host/redirect rejection;
- manifest package, version, schema, filename, size, and digest checks;
- unchanged hash reuse from the active generation;
- a CDN propagation `404` remaining retryable;
- a hash or semantic failure leaving the active pointer unchanged, with only
  the semantic failure recording a rejected version;
- skipping the same rejected version until either package or reader revision
  changes;
- restored background sessions resuming metadata, manifest, and file phases;
  and
- a first remote refresh from the bundle reusing unchanged files and activating
  the six-file candidate atomically.

All validation, storage, widget, activation, and #234 regression tests from the
remote refresh design remain required.

## Rollout

1. Create `openwatersio/slackwater-catalog`, move the existing generators and
   tests, pin inputs, and publish `0.1.0` whose six files are byte-identical to
   the current app bundle.
2. Configure npm trusted publishing after the bootstrap release and verify the
   complete exact-version CDN surface.
3. Change the iOS repository's bundle-generation path to consume the exact npm
   package, keeping the same committed resource bytes.
4. Implement npm discovery, manifest/file download, rejected-version memory,
   and the already designed validation and activation lifecycle.
5. Ship the app with a bundle matching a known package version. Later catalog
   releases exercise the remote path.

There is no Cloudflare migration or dual-publish period because the Worker
delivery path has not shipped. Existing app versions know only their bundle;
the first npm-aware app can be released after `0.1.0` is verified.

## Non-goals

- A product-neutral tides-and-currents schema.
- Client-side composition of upstream source packages.
- npm tarball extraction in the iOS app.
- Delta packages, region packs, or per-station downloads.
- Automatic publication on every dependency or `main` update.
- A custom CDN, Worker, object store, mirror, pointer service, or purge API.
- GitHub release assets duplicating the npm package.
- Remote CHS fitted models or online prediction windows.
- Application-level signing, key rotation, analytics, or a refresh UI.
