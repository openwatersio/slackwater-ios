# TestFlight — headless signing & upload

Set up 2026-07-30 under Bryan's Apple account (Team `R3H8DPTV9C`). Run `scripts/testflight.sh`
to archive + upload; everything below is the one-time state it relies on, and how to rebuild it.

## The pieces

| Piece | Where | Notes |
|---|---|---|
| ASC API key | `~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8` (Key ID `VM6W5HP585`, Issuer `69a6de81-5896-47e3-e053-5b8c7c11a4d1`, role App Manager) | Signs API requests + authenticates the upload. Re-mint at App Store Connect → Users and Access → Integrations |
| Bundle ID (app) | `org.openwaters.slackwater` (ASC id `D696FS7JD3`) | Registered in ASC (one-time, 2026-07) |
| Bundle ID (appex) | `org.openwaters.slackwater.widgets` (ASC id `BC99FA5V78`) | Registered 2026-08-23 for the widget extension. An appex needs its own bundle ID **and its own profile** — the app's covers neither |
| App Group | `group.org.openwaters.slackwater` | Shared by app + appex (`Slackwater.entitlements`, `SlackwaterWidgets.entitlements`); how the widget reads the fitted model and the Premium entitlement. **Created in the developer.apple.com UI — `/v1/appGroups` is a 404, App Groups are not in the ASC API at all** |
| Distribution identity | `slackwater-ci.keychain-db` — "Apple Distribution: Bryan Clark (R3H8DPTV9C)", expires 2027-07-30 (cert `D5456R8W23`) | Key generated locally (openssl CSR → `asc.mjs create-cert`); keychain password in `~/.appstoreconnect/ci-keychain-pass` |
| Provisioning profiles | "Slackwater App Store" (`JZRK3RW824`) **and** "Slackwater Widgets App Store" (`8395577WG2`), both re-minted 2026-08-23 and installed in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` under their UUID filename | `asc.mjs create-profile <bundleIdentifier> D5456R8W23 <out> [profileName]` — the name defaults to "Slackwater App Store", so the appex **must** pass its own or it deletes the app's profile and mints a duplicate wearing the app's name. **Both are needed**, and both must post-date the App Groups capability: a profile minted before a capability was added carries an empty `application-groups` array and the archive fails with entitlement errors. The predecessor `LF393ZYMCC` (2026-07-30) was replaced because it predated widgets |
| Signing config | `project.yml`: Release = manual signing, "Apple Distribution" + the profile; Debug stays automatic | |

## Why the dedicated keychain (the gotcha that cost the afternoon)

Non-GUI sessions (agents, launchd, ssh) see the **login keychain as locked** — codesign fails
with `errSecInternalComponent`, `-allowProvisioningUpdates` cloud signing dies with "User
interaction is not allowed", and `set-key-partition-list` on the login keychain doesn't help
because the lock, not the ACL, is the blocker. The fix is the CI-standard one: a dedicated
keychain whose password lives on disk, unlocked by the script per run, holding a distribution
identity minted through the ASC API (no Xcode sign-in anywhere). Cloud-managed signing is never
used; certificate renewal (2027-07) = new CSR → `asc.mjs create-cert` → import → new profile.

## Tester groups

| Group | Kind | Gets builds | Link |
|---|---|---|---|
| Nightly | internal (`hasAccessToAllBuilds`) | every upload, automatically, no review | — |
| Friends & Family | external, public link | only what `asc.mjs promote` adds, **after Apple beta review** | https://testflight.apple.com/join/HK7mHF19 |

The public link is written down here because it exists nowhere else in the repo — App Store
Connect mints it and `asc.mjs` never reads it back. Re-read it any time with
`GET /v1/betaGroups` → the group's `attributes.publicLink` (`publicLinkEnabled` is the
on/off switch, `publicLinkLimit` the tester cap, currently unset).

Before handing the link to anyone, check what they'd actually install: `node scripts/asc.mjs
builds` shows group membership, but membership is not availability — an external build sits
in `WAITING_FOR_REVIEW` until Apple clears it, and testers keep getting the last **approved**
build meanwhile. Build 25 was in the group and pending review the day it shipped.

## Adding a capability breaks every existing profile (2026-08-23)

Build 28 was merged, approved, and dead on arrival: `xcodebuild archive` failed with
six errors, all of them App Groups. The suite had been green twice on both simulators.
It could not have helped — simulator builds sign with a wildcard development profile
and ignore entitlements the archive enforces.

The order that works, when a target gains an entitlement:

1. **Register the bundle ID** if it is new (`POST /v1/bundleIds`). An app extension
   is a separate bundle ID; the app's does not cover it.
2. **Create the App Group in the developer.apple.com UI.** There is no API —
   `/v1/appGroups` returns 404 `NOT_FOUND`, "the path provided does not match a
   defined resource type". Enable App Groups on *each* bundle ID and assign the group.
3. **Re-mint every affected profile.** Profiles are snapshots: "Slackwater App Store"
   was minted 2026-07-30, long before the entitlement existed, and adding the
   capability does not retroactively update it.
4. **Give the appex a `Release` block in `project.yml`.** Without one it stays on
   `CODE_SIGN_STYLE: Automatic` and Release falls back to
   `"iOS Team Provisioning Profile: *"` — which needs a GUI session to mint, so a
   headless archive simply fails.
5. **Add the appex to `exportOptions`' `provisioningProfiles` dict** in
   `testflight.sh`. A missing entry fails the export *after* a successful archive.

Verify before archiving, rather than after:

```sh
node scripts/asc.mjs builds     # highest build already on ASC
# Does the profile carry the group, and is it bound to the bundle you think?
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  security cms -D -i "$f" | plutil -p - \
    | grep -E '^  "Name"|application-identifier"|group\.'
done
```

**Check `application-identifier`, not just the name.** `filter[identifier]` on
`/v1/bundleIds` is a **prefix** match: it returns `org.openwaters.slackwater` *and*
`org.openwaters.slackwater.widgets`, appex first. `create-profile` took `data[0]`,
so the first mint after the appex was registered produced a profile **named**
"Slackwater App Store" and **bound to the widget's bundle id** — success message,
right name, wrong profile. Fixed by matching the identifier exactly; the check
above is what caught it.

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
- **Fill bundle refit is a release-time decision, not a sync** (`fill-salish.bin`,
  2026-08-21). Fitted constants do not expire; ship the committed bundle as-is
  unless SSCOFS revises its mesh/model or new stations change certification.
  Refit = re-run `tools/fill-pipeline/` end-to-end (README there; ~5 h fetch +
  hours of compute + the size gate + re-pin the real golden in
  `FillFieldTests`). The header JSON records corpus window + mesh hash — check
  those before assuming a refit is needed.

## Test runs — fast by default, full before an upload (2026-08-01)

One XCTestPlan (`TestPlans/Slackwater.xctestplan`), checked in and wired into the
scheme by `project.yml`. The live-IWLS / on-device-fit UI tests carry
`skipUnlessFull()` (ScreenshotTests) and skip themselves unless `SLACKWATER_FULL`
reaches the UI-test runner — `scripts/test.sh --full` sets
`TEST_RUNNER_SLACKWATER_FULL=1`, the same `TEST_RUNNER_` route as `M1_SHOT_DIR`
below. Drive it with `scripts/test.sh`, which prints a per-sim wall clock.

**Fast is iPhone 17 only; `--full` adds the iPad** (Pro 11-inch (M5)). Measured on
build 27, the iPad leg costs 1169 s and is the only place three tests run —
`testM44IPadSplit`, `testM50DetailSwapsBetweenSameKindStations`,
`testM52IPadAutoSelectsTheFirstStation`, 100 s between them. The other 34 UI tests
it runs are a second rendering of what the iPhone leg just proved, so it is a
pre-release check rather than an every-commit one.

```sh
./scripts/test.sh                                  # fast run  — iPhone only, the default
./scripts/test.sh --full                           # full run  — both sims + live-IWLS tests
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

| Mode | Devices | Contents | Wall clock |
|---|---|---|---|
| **Fast** (default) | iPhone 17 | unit tests + the UI tests that run on stored/mocked state | **~15 min** (876 s measured, build 27) |
| **Full** (`--full`) | + iPad Pro 11-inch (M5) | everything: + the live-IWLS / on-device-fit UI tests, the iPad leg, and the national hybrid-direction sweep | **35 min+**, variable |

Figures re-measured at build 27 from `build/results-fast-*.xcresult`. The old
"9 min/sim" in this table predated the worldwide tide bundle and was stale by
roughly 2x. Where the fast run's time actually goes: 50 UI tests are 814 s of it;
the whole 151-test unit target is **21 s**, of which
`testHybridDirectionHasFullCoverageAndMatchesBaseline` alone is 18 s (it sweeps
every bundled station, so it rides `--full` — `scripts/test.sh` skips it by name
in fast mode).

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

## Card contrast — amber against the flat card background (2026-08-02)

**#93 deleted `ProvisionalBadge`** (the fast answer is now `CardStatus.refining`'s strip —
icon, word and the gate's own tolerance, where the badge was a triangle to decode). The
numbers below are why that strip can be plain amber text: at 4.71:1 worst case it clears AA
for text, not just 1.4.11's 3:1 for the icon beside it, so the marking no longer needs its own
opaque disc. `CardStatus.tint` cites this section.


Superseded by M53 (layout A): the per-station `stationGradient`/`gradientTrios` this section
used to warn about are deleted — every card background is now flat `SN.cardFill` (≈5% white)
composited over the list's `SN.canvas`/`SN.canvasGlow` radial ground, so there is no longer a
12-trio worst case to chase. The badge kept its own opaque chrome (amber on an `SN.canvas` disc
with a full-strength amber ring) for the gradients' sake; against the flat fill that measured
below, bare coloured text clears the bar on its own.

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
