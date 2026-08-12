# TestFlight — headless signing & upload

Set up 2026-07-30 under Bryan's Apple account (Team `R3H8DPTV9C`). Run `scripts/testflight.sh`
to archive + upload; everything below is the one-time state it relies on, and how to rebuild it.

## The pieces

| Piece | Where | Notes |
|---|---|---|
| ASC API key | `~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8` (Key ID `VM6W5HP585`, Issuer `69a6de81-5896-47e3-e053-5b8c7c11a4d1`, role App Manager) | Signs API requests + authenticates the upload. Re-mint at App Store Connect → Users and Access → Integrations |
| Bundle ID | `org.openwaters.slackwater` (ASC id `D696FS7JD3`) | Registered in ASC (one-time, 2026-07) |
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

Per-release procedure lives in the `releasing-to-testflight` skill
(`.claude/skills/`) — bump, test, PR, upload, verify. What follows is the state
that procedure sits on.

- Bump `CURRENT_PROJECT_VERSION` in `project.yml` per upload (App Store Connect rejects reused
  build numbers per version); `MARKETING_VERSION` per release. **Both reach the bundle only
  because `info.properties` maps them to `CFBundleVersion` / `CFBundleShortVersionString` and
  the export sets `manageAppVersionAndBuildNumber` `<false/>`** — through build 21 neither was
  wired, Xcode renumbered every upload itself, and every build shipped as `1.0`. Check the
  result with `node scripts/asc.mjs builds`.
- App record ("Slackwater — Tides & Currents") + tester management stay in the App Store
  Connect UI — records can't be created via the public API.
- Export-only variant (signed .ipa, no upload): `build/exportOptions.plist` with
  `destination: export` — what the first proof run used.

## Test runs — fast by default, full before an upload (2026-08-01)

One XCTestPlan (`TestPlans/Slackwater.xctestplan`), checked in and wired into the
scheme by `project.yml`. The live-IWLS / on-device-fit UI tests carry
`skipUnlessFull()` (ScreenshotTests) and skip themselves unless `SLACKWATER_FULL`
reaches the UI-test runner — `scripts/test.sh --full` sets
`TEST_RUNNER_SLACKWATER_FULL=1`, the same `TEST_RUNNER_` route as `M1_SHOT_DIR`
below. Drive it with `scripts/test.sh`, which runs **both reference simulators**
(iPhone 17, iPad Pro 11-inch (M5)) and prints a per-sim wall clock:

```sh
./scripts/test.sh                                  # fast run  — the default
./scripts/test.sh --full                           # full run  — live-IWLS tests included
SHOT_DIR=/tmp/shots ./scripts/test.sh              # where the UI tests save screenshots
SLACKWATER_SIMS='SimA,SimB' ./scripts/test.sh      # run on other devices
```

### One test run at a time (2026-08-02)

The self-hosted runner is this same Mac, so CI and a local run can overlap. When
they do, they SIGKILL each other's test runner: every UI test in the losing run
reports `Test crashed with signal kill` with **zero assertion failures**. It reads
as a real failure and is not one. If you see that signature, check whether
something else was testing at the same time before you debug the code.

Five CI runs died this way on 2026-08-02 — 3, 6 and 16 UI tests at a time — and the
last of them had CI and the local run on *different simulator devices*, so device
separation does not avoid it. The exact kill mechanism was never pinned down; the
CoreSimulator logs had already rolled off. The correlation with overlap was 5 for 5.

So `scripts/test.sh` takes a machine-wide `lockf(1)` lock and whoever arrives second
waits. Your local run can therefore sit for up to a full CI run before it starts —
it prints a line when it's waiting. The lock lives in the kernel, so a killed or
cancelled run releases it and nothing wedges.

Two smaller pieces of the same story:

- `SLACKWATER_SIMS` lets CI run on its own devices (`SlackwaterCI-iPhone` /
  `SlackwaterCI-iPad`, created by the workflow, same device types as the reference
  pair). That doesn't prevent the kill, but it does stop results bleeding between
  overlapping sessions — CI once reported a failing test that didn't exist on the
  branch under test.
- Both modes write screenshots to `/tmp/slackwater-shots` unless `SHOT_DIR` says
  otherwise, CI included, so a local run and CI overwrite each other's images.

| Mode | Contents | Wall clock (per sim) |
|---|---|---|
| **Fast** (default) | all unit tests + the UI tests that run on stored/mocked state | **9 min** (iPhone 534 s, iPad 626 s) |
| **Full** (`--full`) | everything: + the 11 live-IWLS / on-device-fit UI tests | **21 min** (iPhone 1293 s) |

The eleven the fast run skips (each carries `try skipUnlessFull()` at the top —
grep ScreenshotTests.swift for the current list) fetch live from IWLS
(`api-iwls.dfo-mpo.gc.ca`) at the fetcher's 2.5 s pacing and then fit harmonics in
JavaScriptCore (or, for `testOnlineGateLiveFetch`, fetch CHS-published predictions),
so each costs minutes, not seconds.

`testM46MalibuDerivedGate` is the expensive one and the reason the old "12 min" figure was
never reproducible: it launches with no `-chsFitOnly`, so how long Point Atkinson takes to
reach the front of the whole-catalogue queue depends entirely on what that simulator already
had cached. Measured **900 s** on a freshly-reset iPhone sim and 80 s on an iPad sim in the
same run — one test swinging by a quarter of an hour. Full-run runtime therefore varies with
IWLS and with simulator state; 21 min is a good run, not a ceiling.

**Agents: run fast while iterating, run `--full` before `scripts/testflight.sh`.** The full
run is also the only thing that exercises the network path at all, so a green fast run
says nothing about IWLS resolution, chunk caching, or the provisional→final refinement.

Screenshots: `ScreenshotTests` reads `M1_SHOT_DIR` **inside the UI-test runner process**, so
the script exports `TEST_RUNNER_M1_SHOT_DIR` — xcodebuild strips that prefix and sets the
rest on the runner. A bare `M1_SHOT_DIR` in the invoking shell never arrives and the tests
silently fall back to `/tmp`.

## Card contrast — ProvisionalBadge against the flat card background (2026-08-02)

Superseded by M53 (layout A): the per-station `stationGradient`/`gradientTrios` this section
used to warn about are deleted — every card background is now flat `SN.cardFill` (≈5% white)
composited over the list's `SN.canvas`/`SN.canvasGlow` radial ground, so there is no longer a
12-trio worst case to chase. A marking that must read on the card still can't be bare coloured
text, though — `ProvisionalBadge` keeps its own opaque chrome (amber on an `SN.canvas` disc
with a full-strength amber ring) rather than relying on the card fill directly.

Composited card background ranges `#121E35` (deep in the list, near `SN.canvas`) to `#162C4A`
(top of list, near the brighter `SN.canvasGlow`). New amber `#EF6F4A` against that range is
**4.71:1–5.59:1** — clear of WCAG 1.4.11's 3:1 for non-text either way. The glyph-on-disc
contrast (amber icon on the `SN.canvas` disc, 6.25:1) doesn't depend on the card background and
was never the tight number. The prose the badge replaced lives on the detail view's amber card,
which has a controlled background and can afford it.

## CLI vs Xcode GUI — SPM cache isolation (2026-07-31)

CLI builds (testflight.sh and any agent-run `xcodebuild`) must pass
`-clonedSourcePackagesDirPath build/SourcePackages` — a repo-local, gitignored SPM
cache. Without it, a CLI resolve racing the Xcode GUI resolver corrupts the shared
`~/.../org.swift.swiftpm` artifact cache on the MapLibre binary zip ("already exists
in file system" → Resolving Package Graph Failed in Xcode). If the GUI shows that
error: quit Xcode, delete the artifact dir under
`~/Library/Caches/org.swift.swiftpm/artifacts/`, File → Packages → Reset Package
Caches, rebuild.
