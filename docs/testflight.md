# TestFlight — headless signing & upload

Set up 2026-07-30 under Bryan's Apple account (Team `R3H8DPTV9C`). Run `scripts/testflight.sh`
to archive + upload; everything below is the one-time state it relies on, and how to rebuild it.

## The pieces

| Piece | Where | Notes |
|---|---|---|
| ASC API key | `~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8` (Key ID `VM6W5HP585`, Issuer `69a6de81-5896-47e3-e053-5b8c7c11a4d1`, role App Manager) | Signs API requests + authenticates the upload. Re-mint at App Store Connect → Users and Access → Integrations |
| Bundle ID | `org.openwaters.slackwater` (ASC id `D696FS7JD3`) | Registered via `scripts/asc.mjs register-bundle` |
| Distribution identity | `slackwater-ci.keychain-db` — "Apple Distribution: Bryan Clark (R3H8DPTV9C)", expires 2027-07-30 (cert `D5456R8W23`) | Key generated locally (openssl CSR → `asc.mjs create-cert`); keychain password in `~/.appstoreconnect/ci-keychain-pass` |
| Provisioning profile | "Slackwater App Store" (`LF393ZYMCC`), installed in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` | Recreate with `asc.mjs create-profile org.openwaters.slackwater D5456R8W23 out.mobileprovision` (idempotent — deletes stale same-name profile first) |
| Signing config | `project.yml`: Release = manual signing, "Apple Distribution" + the profile; Debug stays automatic | |

## Why the dedicated keychain (the gotcha that cost the afternoon)

Non-GUI sessions (agents, launchd, ssh) see the **login keychain as locked** — codesign fails
with `errSecInternalComponent`, `-allowProvisioningUpdates` cloud signing dies with "User
interaction is not allowed", and `set-key-partition-list` on the login keychain doesn't help
because the lock, not the ACL, is the blocker. The fix is the CI-standard one: a dedicated
keychain whose password lives on disk, unlocked by the script per run, holding a distribution
identity minted through the ASC API (no Xcode sign-in anywhere). Cloud-managed signing is never
used; certificate renewal (2027-07) = new CSR → `asc.mjs create-cert` → import → new profile.

## Cadence

- Bump `CURRENT_PROJECT_VERSION` in `project.yml` per upload (App Store Connect rejects reused
  build numbers per version); `MARKETING_VERSION` per release.
- App record ("Slackwater — Tides & Currents") + tester management stay in the App Store
  Connect UI — records can't be created via the public API.
- Export-only variant (signed .ipa, no upload): `build/exportOptions.plist` with
  `destination: export` — what the first proof run used.

## Test plans — fast by default, full before an upload (2026-08-01)

Two XCTestPlans, both checked in under `TestPlans/` and wired into the scheme by
`project.yml`. Drive them with `scripts/test.sh`, which runs **both reference simulators**
(iPhone 17, iPad Pro 11-inch (M5)) and prints a per-sim wall clock:

```sh
./scripts/test.sh                                  # fast plan  — the default
./scripts/test.sh --full                           # full plan
SHOT_DIR=/tmp/shots ./scripts/test.sh              # where the UI tests save screenshots
```

| Plan | File | Contents | Wall clock (per sim) |
|---|---|---|---|
| **Fast** (default) | `TestPlans/Slackwater.xctestplan` | all 55 unit tests + the 24 UI tests that run on stored/mocked state | **9 min** (iPhone 534 s, iPad 626 s) |
| **Full** | `TestPlans/Slackwater-Full.xctestplan` | everything: + the 9 live-IWLS / on-device-fit UI tests | **21 min** (iPhone 1293 s) |

The nine the fast plan skips — every one of them fetches live from IWLS
(`api-iwls.dfo-mpo.gc.ca`) at the fetcher's 2.5 s pacing and then fits harmonics in
JavaScriptCore, so each costs minutes, not seconds:

```
ScreenshotTests/testM3ChsPendingFitOffline
ScreenshotTests/testM46MalibuDerivedGate
ScreenshotTests/testM47DoddNarrowsPendingFitDetailOffline
ScreenshotTests/testM48DownloadsManagerAndQueueJump
ScreenshotTests/testM51ManagerShowsProvisionalApartFromFinal
ScreenshotTests/testM51NearestTidePortTimeToFirstUsable
ScreenshotTests/testM51PromotionInterruptsAnInFlightDownload
ScreenshotTests/testM51ProvisionalGateShowsFastAnswerThenRefines
ScreenshotTests/testM51ValidatedGateReachesFinalWithNoProvisionalStage
```

`testM46MalibuDerivedGate` is the expensive one and the reason the old "12 min" figure was
never reproducible: it launches with no `-chsFitOnly`, so how long Point Atkinson takes to
reach the front of the whole-catalogue queue depends entirely on what that simulator already
had cached. Measured **900 s** on a freshly-reset iPhone sim and 80 s on an iPad sim in the
same run — one test swinging by a quarter of an hour. Full-plan runtime therefore varies with
IWLS and with simulator state; 21 min is a good run, not a ceiling.

**Agents: run fast while iterating, run `--full` before `scripts/testflight.sh`.** The full
plan is also the only thing that exercises the network path at all, so a green fast plan
says nothing about IWLS resolution, chunk caching, or the provisional→final refinement.

Screenshots: `ScreenshotTests` reads `M1_SHOT_DIR` **inside the UI-test runner process**, so
the script exports `TEST_RUNNER_M1_SHOT_DIR` — xcodebuild strips that prefix and sets the
rest on the runner. A bare `M1_SHOT_DIR` in the invoking shell never arrives and the tests
silently fall back to `/tmp`.

## Card contrast — the sn- gradients are not a safe text background (2026-08-01)

Measured for the M52 provisional-marking fix; the numbers are worth keeping because they
apply to anything anyone is tempted to write onto a station card. Amber `#E0B45A` sits at
almost exactly the luminance of the palette's pale gradient stops:

| Foreground on a station gradient | Best stop | Worst stop |
|---|---|---|
| Amber `#E0B45A` | 9.07:1 (`#00183C`) | **1.03:1** (`#9AC0B0`) — invisible |
| White | 17.56:1 (`#00183C`) | 1.82:1 (`#A8C4D4`) |

So a marking that must read on *every* trio can't be bare coloured text — it needs its own
opaque chrome. `ProvisionalBadge` is amber on an `SN.canvas` disc (9.63:1 glyph-on-disc) with
a full-strength amber ring: the disc reads 10.22:1 against the palest stop, the ring 9.07:1
against the darkest, and the better of the two boundaries is ≥3.14:1 on every stop in the
palette — clear of WCAG 1.4.11's 3:1 for non-text. The prose it replaced lives on the detail
view's amber card, which has a controlled background and can afford it.

## CLI vs Xcode GUI — SPM cache isolation (2026-07-31)

CLI builds (testflight.sh and any agent-run `xcodebuild`) must pass
`-clonedSourcePackagesDirPath build/SourcePackages` — a repo-local, gitignored SPM
cache. Without it, a CLI resolve racing the Xcode GUI resolver corrupts the shared
`~/.../org.swift.swiftpm` artifact cache on the MapLibre binary zip ("already exists
in file system" → Resolving Package Graph Failed in Xcode). If the GUI shows that
error: quit Xcode, delete the artifact dir under
`~/Library/Caches/org.swift.swiftpm/artifacts/`, File → Packages → Reset Package
Caches, rebuild.
